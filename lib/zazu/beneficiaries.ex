defmodule Zazu.Beneficiaries do
  @moduledoc """
  Saved transfer recipients.

  Each beneficiary embeds its bank accounts (`"external_accounts"`); the one
  flagged `default` is used when a transfer names only the `beneficiary_id`.
  Beneficiaries and their bank accounts can be created via the API; there is
  no update or delete.
  """

  alias Zazu.Client

  @doc """
  Calls `GET /api/beneficiaries`.

  ## Options

    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(client, "api/beneficiaries", [], opts)
  end

  @doc """
  Calls `GET /api/beneficiaries/:id`.
  """
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/beneficiaries", id]))
  end

  @doc """
  Calls `POST /api/beneficiaries`.

  Keys: `beneficiary_type` (`"individual"` | `"business"`; inferred from
  `person_name` / `company_name` when omitted), `person_name`, `company_name`,
  `email`, `phone_number`. Values must be strings. Shares a 10/minute limit
  with `create_external_account/3`.
  """
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/beneficiaries", attributes)
  end

  @doc """
  Calls `GET /api/beneficiaries/:beneficiary_id/external_accounts`.

  ## Options

    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list_external_accounts(Client.t(), String.t(), keyword()) ::
          {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list_external_accounts(client, beneficiary_id, opts \\ []) do
    path = Client.encode_path(["api/beneficiaries", beneficiary_id, "external_accounts"])
    Client.list_page(client, path, [], opts)
  end

  @doc "Calls `GET /api/beneficiaries/:beneficiary_id/external_accounts/:id`."
  @spec get_external_account(Client.t(), String.t(), String.t()) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get_external_account(client, beneficiary_id, id) do
    Client.get(
      client,
      Client.encode_path(["api/beneficiaries", beneficiary_id, "external_accounts", id])
    )
  end

  @doc """
  Calls `POST /api/beneficiaries/:beneficiary_id/external_accounts`.

  Required: `account_number`. Optional: `name`, `country_code`,
  `currency_code`, `account_type` (`"bank"` only), `bank_identifier`
  (required in ZA, rejected in MA, where it is derived from the RIB).
  """
  @spec create_external_account(Client.t(), String.t(), map()) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create_external_account(client, beneficiary_id, attributes) do
    Client.post(
      client,
      Client.encode_path(["api/beneficiaries", beneficiary_id, "external_accounts"]),
      attributes
    )
  end
end
