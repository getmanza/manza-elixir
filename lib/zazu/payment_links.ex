defmodule Zazu.PaymentLinks do
  @moduledoc "Standalone payment links (not attached to an invoice)."

  alias Zazu.Client

  @doc """
  Calls `GET /api/payment_links`.

  ## Options

    * `:status` — filter by link status.
    * `:link_type` — filter by link type (`"single"` / `"reusable"`).
    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(
      client,
      "api/payment_links",
      Client.query_filters(opts, [:status, :link_type]),
      opts
    )
  end

  @doc "Calls `GET /api/payment_links/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/payment_links", id]))
  end

  @doc "Calls `POST /api/payment_links`."
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/payment_links", attributes)
  end

  @doc "Calls `POST /api/payment_links/:id/cancel`."
  @spec cancel(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def cancel(client, id) do
    Client.post(client, Client.encode_path(["api/payment_links", id, "cancel"]))
  end
end
