defmodule Zazu.Test.CassetteReplay do
  @moduledoc """
  Reads VCR YAML cassettes (recorded by zazu-ruby) and serves them from a
  Bypass server so identical interactions replay against this SDK. The
  contract is enforced cross-language: every SDK that consumes the cassette
  tarball must replay the exact request shape.

  Matching is method + path+query (ignoring host) + semantic JSON body
  (both sides are decoded and compared as terms, so key ordering and
  whitespace differences between Ruby's and Elixir's encoders never matter).

  Load ONE cassette per test when two cassettes share method + URI
  (`transfer_drafts/authorize` vs `authorize_same_key`, `create` vs
  `create_duplicate`): the first matching interaction wins.

  The authorize cassettes are loaded with `ignore_signature: true`: their
  recorded `signature` is scrubbed to `<SIGNATURE>` (the real one is an HMAC
  over the real nonce and secret, which replay cannot reproduce), so the
  match is method + URI + body with `signature` removed. This mirrors the
  Ruby `body_without_signature` matcher.

  Ruby's Psych writes non-UTF-8 bodies as base64 with the PRIMARY `!binary`
  tag (not the canonical `!!binary`), which yamerl rejects as an
  unrecognized node — so the tag is rewritten to a `binary_string` key
  before parsing and base64-decoded ourselves, like zazu-go does.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @cassette_dir Path.join([__DIR__, "..", "..", "testdata", "cassettes"])

  @doc """
  Loads the named cassettes (e.g. `"payment_links/list"`) and serves their
  interactions from a Bypass server. Returns a `Zazu.Client` pointed at it.
  Unmatched requests get a 501, which fails the calling assertion.

  Options: `ignore_signature: true` drops the `"signature"` key from both
  request bodies before comparing.
  """
  def replay_client(names, opts \\ []) do
    ignore_signature = Keyword.get(opts, :ignore_signature, false)
    interactions = Enum.flat_map(names, &load_cassette/1)
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case Enum.find(interactions, &matches?(&1, conn, body, ignore_signature)) do
        nil ->
          Plug.Conn.send_resp(
            conn,
            501,
            "no cassette interaction matches #{conn.method} #{conn.request_path}?#{conn.query_string} (body #{inspect(body)})"
          )

        interaction ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(interaction.status, interaction.response_body)
      end
    end)

    Zazu.new!(api_key: "test-api-key-for-replay", base_url: "http://localhost:#{bypass.port}")
  end

  defp load_cassette(name) do
    path = Path.join(@cassette_dir, name <> ".yml")

    raw =
      case File.read(path) do
        {:ok, raw} ->
          raw

        {:error, reason} ->
          flunk("read cassette #{path}: #{reason} (run scripts/fetch-cassettes.sh first)")
      end

    parsed =
      raw
      # yamerl can't decode VCR's primary `!binary` tag — rewrite it to a
      # dedicated key and Base.decode64 it ourselves (covers `|` and `|-`).
      |> String.replace("string: !binary |", "binary_string: |")
      |> YamlElixir.read_from_string!()

    for interaction <- parsed["http_interactions"] do
      request = interaction["request"]
      response = interaction["response"]
      uri = URI.parse(request["uri"])

      %{
        method: String.upcase(request["method"] || ""),
        path: uri.path,
        query: URI.decode_query(uri.query || ""),
        request_body: body_string(request["body"]),
        status: response["status"]["code"],
        response_body: body_string(response["body"])
      }
    end
  end

  defp body_string(%{"binary_string" => encoded}) when is_binary(encoded) do
    encoded |> String.replace(~r/\s/, "") |> Base.decode64!()
  end

  defp body_string(%{"string" => string}) when is_binary(string), do: string
  defp body_string(_body), do: ""

  defp matches?(interaction, conn, body, ignore_signature) do
    interaction.method == conn.method and
      interaction.path == conn.request_path and
      interaction.query == URI.decode_query(conn.query_string) and
      json_equal?(interaction.request_body, body, ignore_signature)
  end

  # Compares two bodies semantically when both parse as JSON, and
  # byte-for-byte otherwise (empty matches empty).
  defp json_equal?(recorded, actual, false) when recorded == actual, do: true

  defp json_equal?(recorded, actual, ignore_signature) do
    with {:ok, a} <- Jason.decode(recorded),
         {:ok, b} <- Jason.decode(actual) do
      strip_signature(a, ignore_signature) == strip_signature(b, ignore_signature)
    else
      _ -> false
    end
  end

  defp strip_signature(%{} = body, true), do: Map.delete(body, "signature")
  defp strip_signature(body, _ignore_signature), do: body
end
