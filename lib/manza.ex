defmodule Manza do
  @moduledoc """
  Elixir SDK for the [Manza](https://get-manza.com) API.

  Response bodies are returned as-is from the API — snake_case string-keyed
  maps, no struct mapping. The same shape ships across every Manza SDK (Ruby,
  TypeScript, Python, Go, ...) so the cassette contract is one-to-one.

      {:ok, client} = Manza.new(api_key: System.fetch_env!("MANZA_API_KEY"))

      {:ok, entity} = Manza.Entity.get(client)

      {:ok, page} = Manza.Accounts.list(client)

      for account <- page.data do
        IO.puts("\#{account["id"]} \#{account["name"]}")
      end
  """

  @version Mix.Project.config()[:version]

  @doc "The SDK version, sent in the `User-Agent` header."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Builds a `Manza.Client`. An API key is required — pass `:api_key` or set
  `MANZA_API_KEY`.

  ## Options

    * `:api_key` — the Manza API key (default: the `MANZA_API_KEY` env var).
      Sent as `Authorization: Bearer <key>`.
    * `:base_url` — the API base URL (default: `MANZA_BASE_URL` or
      `https://ma.manza.finance`; use `https://za.manza.finance` for South
      Africa).
    * `:api_version` — pins the `Manza-Version` request header (default:
      `MANZA_API_VERSION`).
    * `:timeout` — receive timeout in milliseconds (default: `30_000`).

  Returns `{:ok, %Manza.Client{}}` or `{:error, %Manza.ConfigurationError{}}`.
  """
  @spec new(keyword()) :: {:ok, Manza.Client.t()} | {:error, Manza.ConfigurationError.t()}
  defdelegate new(opts \\ []), to: Manza.Client

  @doc """
  Same as `new/1` but raises `Manza.ConfigurationError` on invalid config.
  """
  @spec new!(keyword()) :: Manza.Client.t()
  defdelegate new!(opts \\ []), to: Manza.Client
end
