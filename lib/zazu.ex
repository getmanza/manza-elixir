defmodule Zazu do
  @moduledoc """
  Elixir SDK for the [Zazu](https://zazu.ma) API.

  Response bodies are returned as-is from the API — snake_case string-keyed
  maps, no struct mapping. The same shape ships across every Zazu SDK (Ruby,
  TypeScript, Python, Go, ...) so the cassette contract is one-to-one.

      {:ok, client} = Zazu.new(api_key: System.fetch_env!("ZAZU_API_KEY"))

      {:ok, entity} = Zazu.Entity.get(client)

      {:ok, page} = Zazu.Accounts.list(client)

      for account <- page.data do
        IO.puts("\#{account["id"]} \#{account["name"]}")
      end
  """

  @version Mix.Project.config()[:version]

  @doc "The SDK version, sent in the `User-Agent` header."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Builds a `Zazu.Client`. An API key is required — pass `:api_key` or set
  `ZAZU_API_KEY`.

  ## Options

    * `:api_key` — the Zazu API key (default: the `ZAZU_API_KEY` env var).
      Sent as `Authorization: Bearer <key>`.
    * `:base_url` — the API base URL (default: `ZAZU_BASE_URL` or
      `https://ma.manza.finance`; use `https://za.manza.finance` for South
      Africa).
    * `:api_version` — pins the `Zazu-Version` request header (default:
      `ZAZU_API_VERSION`).
    * `:timeout` — receive timeout in milliseconds (default: `30_000`).

  Returns `{:ok, %Zazu.Client{}}` or `{:error, %Zazu.ConfigurationError{}}`.
  """
  @spec new(keyword()) :: {:ok, Zazu.Client.t()} | {:error, Zazu.ConfigurationError.t()}
  defdelegate new(opts \\ []), to: Zazu.Client

  @doc """
  Same as `new/1` but raises `Zazu.ConfigurationError` on invalid config.
  """
  @spec new!(keyword()) :: Zazu.Client.t()
  defdelegate new!(opts \\ []), to: Zazu.Client
end
