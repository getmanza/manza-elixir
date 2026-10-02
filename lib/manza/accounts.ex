defmodule Manza.Accounts do
  @moduledoc "Accounts and their transactions."

  alias Manza.Client

  @doc """
  Calls `GET /api/accounts`.

  ## Options

    * `:status` — filter by account status.
    * `:currency_code` — filter by currency code.
    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Manza.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(
      client,
      "api/accounts",
      Client.query_filters(opts, [:status, :currency_code]),
      opts
    )
  end

  @doc "Calls `GET /api/accounts/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/accounts", id]))
  end

  @doc """
  Calls `GET /api/accounts/:account_id/transactions`.

  ## Options

    * `:operation` — filter by operation (`"credit"` / `"debit"`).
    * `:posted_after` — ISO-8601 lower bound.
    * `:posted_before` — ISO-8601 upper bound.
    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list_transactions(Client.t(), String.t(), keyword()) ::
          {:ok, Manza.Page.t()} | {:error, Exception.t()}
  def list_transactions(client, account_id, opts \\ []) do
    Client.list_page(
      client,
      Client.encode_path(["api/accounts", account_id, "transactions"]),
      Client.query_filters(opts, [:operation, :posted_after, :posted_before]),
      opts
    )
  end

  @doc "Calls `GET /api/accounts/:account_id/transactions/:id`."
  @spec get_transaction(Client.t(), String.t(), String.t()) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get_transaction(client, account_id, transaction_id) do
    Client.get(
      client,
      Client.encode_path(["api/accounts", account_id, "transactions", transaction_id])
    )
  end
end
