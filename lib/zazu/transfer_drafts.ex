defmodule Zazu.TransferDrafts do
  @moduledoc """
  API-initiated transfers.

  Creating a transfer draft never executes a transfer by itself. A draft
  inside the entity's machine-authorization envelope (trusted payee, within
  limits) is sent to the enrolled transfer authorizer as a
  `payment.authorization_requested` webhook; answer it with `authorize/5` or
  `decline/4`, using an API key other than the one that created the draft.
  Every other draft goes to the in-app approval flow, where a manager or legal
  representative approves it. Poll `get/2` (status: `requested` →
  `processing` → `completed` / `failed`) or subscribe to the
  `transfer.executed` webhook to follow execution.
  """

  alias Zazu.Client

  @doc """
  Calls `POST /api/transfer_drafts`.

  The draft is created with status `"requested"` and a `nil` `"transfer"`
  until it is authorized.

  Required attributes: `account_id`, `amount`, and exactly one of
  `beneficiary_id` (external transfer) or `destination_account_id`
  (own-account move).

  Optional attributes: `external_account_id`, `currency_code`,
  `payment_reference`, `internal_notes`, and `client_reference` (unique per
  entity, at most 128 characters; a duplicate returns
  `{:error, %Zazu.Error{kind: :conflict}}` whose `payment_id` names the
  existing draft). The response carries `client_reference` and
  `authorization` (`%{"id", "status", "expires_at"}` or `nil`).
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

  @doc """
  Calls `POST /api/transfer_drafts/:id/authorize`.

  Executes the draft. `authorization_id` comes from the
  `payment.authorization_requested` webhook; build `signature` with
  `Zazu.TransferAuthorization`. Requires the `transfers:authorize` scope on a
  key other than the draft's creator (otherwise 403 `same_key_forbidden`).

  A blank `signature` is refused locally with
  `{:error, %Zazu.ConfigurationError{}}` before any HTTP call: the API counts
  it as a failed attempt, and five fail the challenge.
  """
  @spec authorize(Client.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def authorize(client, id, authorization_id, signature) do
    if blank?(signature) do
      {:error, %Zazu.ConfigurationError{message: "signature cannot be blank"}}
    else
      Client.post(client, Client.encode_path(["api/transfer_drafts", id, "authorize"]), %{
        "authorization_id" => authorization_id,
        "signature" => signature
      })
    end
  end

  @doc """
  Calls `POST /api/transfer_drafts/:id/decline`.

  Declines the challenge and deletes the draft. Returns the authorization
  (`"status" => "declined"`). `reason` is omitted from the request when `nil`.
  """
  @spec decline(Client.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def decline(client, id, authorization_id, reason \\ nil) do
    body =
      if reason,
        do: %{"authorization_id" => authorization_id, "reason" => reason},
        else: %{"authorization_id" => authorization_id}

    Client.post(client, Client.encode_path(["api/transfer_drafts", id, "decline"]), body)
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
