defmodule Manza.PayeeTrustRequests do
  @moduledoc """
  Requests to trust payees for machine-authorized transfers.

  The API key can only ask: a member holding payment-authorize permission
  approves the request in the Manza app. Status: `pending` → `approved` /
  `declined` / `cancelled`. There is no list, update, or delete.
  """

  alias Manza.Client

  @doc """
  Calls `POST /api/payee_trust_requests`.

  `external_account_ids` is a list of at most 100 bank account ids.
  """
  @spec create(Client.t(), [String.t()]) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def create(client, external_account_ids) do
    Client.post(client, "api/payee_trust_requests", %{
      "external_account_ids" => external_account_ids
    })
  end

  @doc "Calls `GET /api/payee_trust_requests/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/payee_trust_requests", id]))
  end
end
