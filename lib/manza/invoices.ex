defmodule Manza.Invoices do
  @moduledoc "Invoices and their lifecycle actions."

  alias Manza.Client

  @doc """
  Calls `GET /api/invoices`.

  ## Options

    * `:status` — filter by invoice status: `draft`, `pending_approval`,
      `declined`, `approved`, `sent`, `paid`, `overdue` or `cancelled`.
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

  Required: `customer_id`, `account_id` (the entity's account the invoice is
  paid into, from `Manza.Accounts.list/2`; without one the API answers 422
  `type` `"state_error"`, and an account that is not the entity's 422 with
  `param` `"account_id"`), `issue_date`, `due_date` and `items`. Optional:
  `currency_code`, `reference`, `notes`, `payment_terms`, `send_to_email`,
  `discounts`, `delivery_date` (Morocco only) and `generate_payment_link`.

  `"generate_payment_link" => true` asks for a card payment link, made from
  the invoice's account when the invoice is approved; it needs the
  `payment_links:write` scope and is taken only while payment links are
  enabled for the entity. A boolean, `nil` (no link) or the strings `"true"`,
  `"false"`, `"1"` and `"0"` are taken; any other value returns a 400
  `:validation` error and nothing is created. It replaces the removed
  `create_payment_link` function.

  `tax_rate` must be the issuer's rate or 0, otherwise 422. The market-gated
  `delivery_date` key is absent outside Morocco. The response carries
  `generate_payment_link`, the embedded `account` (`id`, `name`,
  `currency_code`, and `rib` in Morocco or `account_number` in South Africa)
  and `payment_link` once one exists. A plan that caps invoices returns
  `{:error, %Manza.Error{kind: :plan_limit_reached}}`.
  """
  @spec create(Client.t(), map()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/invoices", attributes)
  end

  @doc """
  Calls `PATCH /api/invoices/:id`.

  Takes the create fields, `account_id` and `generate_payment_link` included
  (the same scope and entity rule apply), on an invoice that is still
  editable.
  """
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

  @doc """
  Calls `DELETE /api/invoices/:id`.

  Only a `draft`, `pending_approval` or `declined` invoice that has no number
  yet; any other returns a 422 `:validation` error (`type` `"state_error"`).
  """
  @spec delete(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def delete(client, id) do
    Client.delete(client, Client.encode_path(["api/invoices", id]))
  end
end
