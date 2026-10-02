defmodule Zazu.Client do
  @moduledoc """
  The SDK entry point. Build one with `Zazu.new/1` and pass it as the first
  argument to every resource function (`Zazu.Accounts`, `Zazu.Invoices`, ...).
  """

  defstruct [:api_key, :base_url, :api_version, :timeout]

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          api_version: String.t() | nil,
          timeout: pos_integer()
        }

  @default_base_url "https://ma.manza.finance"
  @default_timeout 30_000

  @doc false
  @spec new(keyword()) :: {:ok, t()} | {:error, Zazu.ConfigurationError.t()}
  def new(opts \\ []) do
    api_key = opts[:api_key] || env("ZAZU_API_KEY")
    base_url = opts[:base_url] || env("ZAZU_BASE_URL") || @default_base_url

    if api_key in [nil, ""] do
      {:error,
       %Zazu.ConfigurationError{message: "missing API key: pass :api_key or set ZAZU_API_KEY"}}
    else
      {:ok,
       %__MODULE__{
         api_key: api_key,
         base_url: String.trim_trailing(base_url, "/"),
         api_version: opts[:api_version] || env("ZAZU_API_VERSION"),
         timeout: opts[:timeout] || @default_timeout
       }}
    end
  end

  @doc false
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc """
  Performs an HTTP request against the API.

  Non-2xx responses come back as `{:error, %Zazu.Error{}}`; transport
  failures as `{:error, %Zazu.ConnectionError{}}`. `body` (when non-nil) is
  JSON-encoded.
  """
  @spec request(t(), atom(), String.t(), keyword() | map(), map() | nil) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def request(%__MODULE__{} = client, method, path, query \\ [], body \\ nil) do
    url = client.base_url <> "/" <> String.trim_leading(path, "/")

    request =
      Req.new(
        method: method,
        url: url,
        params: query,
        headers: headers(client, body),
        body: if(body, do: Jason.encode!(body)),
        receive_timeout: client.timeout,
        retry: false,
        decode_body: false
      )

    case Req.request(request) do
      {:ok, %Req.Response{} = response} ->
        handle_response(response)

      {:error, exception} ->
        {:error, %Zazu.ConnectionError{message: Exception.message(exception), reason: exception}}
    end
  end

  @doc false
  def get(client, path, query \\ []), do: request(client, :get, path, query, nil)

  @doc false
  def post(client, path, body \\ nil), do: request(client, :post, path, [], body)

  @doc false
  def patch(client, path, body), do: request(client, :patch, path, [], body)

  @doc false
  def delete(client, path), do: request(client, :delete, path, [], nil)

  @doc false
  @spec list_page(t(), String.t(), keyword(), keyword()) ::
          {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list_page(%__MODULE__{} = client, path, base_query, opts) do
    limit = Keyword.get(opts, :limit, Zazu.Page.max_per_page())
    cursor = Keyword.get(opts, :cursor)

    if is_integer(limit) and limit >= 1 and limit <= Zazu.Page.max_per_page() do
      fetch_page(client, path, base_query, limit, cursor)
    else
      {:error,
       %Zazu.ConfigurationError{
         message:
           "limit must be between 1 and #{Zazu.Page.max_per_page()} (got #{inspect(limit)})"
       }}
    end
  end

  defp fetch_page(client, path, base_query, limit, cursor) do
    query =
      base_query
      |> Keyword.put(:limit, limit)
      |> then(fn q -> if cursor, do: Keyword.put(q, :cursor, cursor), else: q end)

    with {:ok, response} <- get(client, path, query) do
      fetch = fn next_cursor -> fetch_page(client, path, base_query, limit, next_cursor) end
      {:ok, Zazu.Page.from_response(response, fetch)}
    end
  end

  @doc """
  Joins path segments, URI-escaping each one. Segments may contain literal
  `/` separators (`"api/invoices"`); everything between separators is
  escaped.
  """
  @spec encode_path([String.t()]) :: String.t()
  def encode_path(segments) when is_list(segments) do
    segments
    |> Enum.flat_map(&String.split(&1, "/"))
    |> Enum.map_join("/", &URI.encode(&1, fn char -> URI.char_unreserved?(char) end))
  end

  @doc false
  def query_filters(opts, keys) do
    for key <- keys, value = opts[key], value not in [nil, ""], do: {key, to_string(value)}
  end

  defp headers(client, body) do
    [
      {"authorization", "Bearer " <> client.api_key},
      {"user-agent", "zazu-elixir/" <> Zazu.version()},
      {"accept", "application/json"}
    ]
    |> then(fn h -> if body, do: h ++ [{"content-type", "application/json"}], else: h end)
    |> then(fn h ->
      if client.api_version, do: h ++ [{"zazu-version", client.api_version}], else: h
    end)
  end

  defp handle_response(%Req.Response{status: status, headers: headers, body: raw}) do
    raw = if is_binary(raw), do: raw, else: IO.iodata_to_binary(raw || [])
    body = parse_json(raw)

    if status in 200..299 do
      {:ok,
       %Zazu.Response{
         status: status,
         request_id: header_value(headers, "x-request-id"),
         body: body,
         raw: raw,
         headers: headers
       }}
    else
      {:error, Zazu.Error.from_response(status, headers, body)}
    end
  end

  # Non-JSON bodies stay raw on the response; the parsed body stays empty.
  defp parse_json(""), do: %{}

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> %{}
    end
  end

  defp header_value(headers, name) do
    case Map.get(headers, name) do
      [value | _rest] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp env(name) do
    case System.get_env(name) do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end
end
