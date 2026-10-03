defmodule Manza.Invoices do
  @moduledoc "Invoices and their lifecycle actions."

  alias Manza.Client

  @doc """
  Calls `GET /api/invoices`.

  ## Options

    * `:status` — filter by invoice status.
    * `:customer_id` — filter by customer.
    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Manza.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(
      client,
      "api/invoices",
      Client.query_filters(opts, [:status, :customer_id]),
      opts
    )
  end

  @doc "Calls `GET /api/invoices/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/invoices", id]))
  end

  @doc """
  Calls `POST /api/invoices`.

  `tax_rate` must be the issuer's rate or 0, otherwise 422. The market-gated
  `delivery_date` key is absent outside Morocco.
  """
  @spec create(Client.t(), map()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/invoices", attributes)
  end

  @doc "Calls `PATCH /api/invoices/:id`."
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def update(client, id, attributes) do
    Client.patch(client, Client.encode_path(["api/invoices", id]), attributes)
  end

  @doc "Calls `POST /api/invoices/:id/send`."
  @spec send(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def send(client, id) do
    Client.post(client, Client.encode_path(["api/invoices", id, "send"]))
  end

  @doc "Calls `POST /api/invoices/:id/mark_as_paid`."
  @spec mark_as_paid(Client.t(), String.t()) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def mark_as_paid(client, id) do
    Client.post(client, Client.encode_path(["api/invoices", id, "mark_as_paid"]))
  end

  @doc "Calls `POST /api/invoices/:id/cancel`."
  @spec cancel(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def cancel(client, id) do
    Client.post(client, Client.encode_path(["api/invoices", id, "cancel"]))
  end

  @doc "Calls `POST /api/invoices/:id/credit_note`."
  @spec credit_note(Client.t(), String.t()) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def credit_note(client, id) do
    Client.post(client, Client.encode_path(["api/invoices", id, "credit_note"]))
  end

  @doc "Calls `DELETE /api/invoices/:id`."
  @spec delete(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def delete(client, id) do
    Client.delete(client, Client.encode_path(["api/invoices", id]))
  end

  @doc "Calls `POST /api/invoices/:invoice_id/payment_link`."
  @spec create_payment_link(Client.t(), String.t(), String.t()) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def create_payment_link(client, invoice_id, account_id) do
    Client.post(client, Client.encode_path(["api/invoices", invoice_id, "payment_link"]), %{
      "account_id" => account_id
    })
  end
end
