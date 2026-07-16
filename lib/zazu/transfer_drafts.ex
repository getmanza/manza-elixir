defmodule Zazu.TransferDrafts do
  @moduledoc """
  API-initiated transfers.

  Creating a transfer draft routes it into the workspace's in-app approval
  flow — the API never executes a transfer itself. Poll `get/2` (status:
  `requested` → `processing` → `completed` / `failed`) or subscribe to the
  `transfer.executed` webhook.
  """

  alias Zazu.Client

  @doc """
  Calls `POST /api/transfer_drafts`.

  Creating a transfer draft routes it into the workspace's in-app approval
  flow — the API never executes a transfer itself. The draft is created with
  status `"requested"` and a `nil` `"transfer"` until it is approved in-app.

  Required attributes: `account_id`, `amount`, and exactly one of
  `beneficiary_id` (external transfer) or `destination_account_id`
  (own-account move).
  """
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/transfer_drafts", attributes)
  end

  @doc """
  Calls `GET /api/transfer_drafts/:id`.

  Poll this to follow the draft through the in-app approval flow (status:
  `requested` → `processing` → `completed` / `failed`) — the API never
  executes a transfer itself.
  """
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/transfer_drafts", id]))
  end
end
