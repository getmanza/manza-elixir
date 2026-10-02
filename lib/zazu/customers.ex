defmodule Zazu.Customers do
  @moduledoc "Individuals or businesses the entity invoices."

  alias Zazu.Client

  @doc """
  Calls `GET /api/customers`.

  ## Options

    * `:q` — matches company name, person name, email.
    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(client, "api/customers", Client.query_filters(opts, [:q]), opts)
  end

  @doc "Calls `GET /api/customers/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/customers", id]))
  end

  @doc """
  Calls `POST /api/customers`.

  Customers also carry `registration_number` and `vat_number`. The
  market-gated `tax_id` and `ice_number` keys are absent outside Morocco.
  """
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/customers", attributes)
  end

  @doc "Calls `PATCH /api/customers/:id`."
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def update(client, id, attributes) do
    Client.patch(client, Client.encode_path(["api/customers", id]), attributes)
  end

  @doc "Calls `DELETE /api/customers/:id`."
  @spec delete(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def delete(client, id) do
    Client.delete(client, Client.encode_path(["api/customers", id]))
  end
end
