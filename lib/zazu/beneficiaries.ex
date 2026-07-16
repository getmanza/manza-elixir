defmodule Zazu.Beneficiaries do
  @moduledoc """
  Read-only directory of saved transfer recipients, managed in the Zazu
  dashboard.

  Each beneficiary embeds its bank accounts (`"external_accounts"`); the one
  flagged `default` is used when a transfer names only the `beneficiary_id`.
  The API cannot create, update, or delete beneficiaries — they are created
  and managed in the dashboard.
  """

  alias Zazu.Client

  @doc """
  Calls `GET /api/beneficiaries`.

  Beneficiaries are a read-only directory managed in the Zazu dashboard —
  the API only lists and reads them.

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

  Beneficiaries are a read-only directory managed in the Zazu dashboard.
  """
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/beneficiaries", id]))
  end
end
