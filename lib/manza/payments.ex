defmodule Manza.Payments do
  @moduledoc """
  API-initiated transfers, called payments (formerly transfer drafts;
  `Manza.TransferDrafts` is a deprecated alias, and the server keeps
  `/api/transfer_drafts` as a permanent alias of `/api/payments`).

  Creating a draft never executes a transfer by itself. A draft
  inside the entity's machine-authorization envelope (trusted payee, within
  limits) is sent to the enrolled transfer authorizer as a
  `payment.authorization_requested` webhook; answer it with `authorize/4` or
  `decline/4`, using an API key other than the one that created the draft.
  Every other draft goes to the in-app approval flow, where a manager or legal
  representative approves it. Poll `get/2` (status: `requested` →
  `processing` → `completed` / `failed`) or subscribe to the
  `transfer.executed` webhook to follow execution.

  A draft's `"authorization"` says which way it went: `"pending"` (a
  challenge was sent), `"authorized"`, `"declined"` (the draft is deleted),
  or one of the outcomes that send the draft to the in-app approvers, each
  with a `"refusal_reason"`:

    * `"refused"`: it did not qualify, at create time (no webhook is sent) or
      again when the challenge was answered: `untrusted_payee`,
      `unrestricted_api_key`, `over_new_payee_limit`, `over_transfer_limit`,
      `over_daily_limit`, `currency_mismatch`, `suspended` or
      `secret_expired`.
    * `"expired"` / `"superseded"` / `"failed"`: a challenge was sent and
      closed without an authorize: `expired` (no answer within the hour),
      `stale` (the draft, its payee's bank details or the endpoint changed
      while it was open) or `signature_failed` (five invalid signatures).

  `"authorization"` is `nil` when no authorizer was enrolled.

  With "Approve transfers to new payees" on (enrolment, in the app), a draft
  to bank details the entity never trusted is challenged too, up to the
  new-payee limit, when the creating key has an IP allowlist; authorizing it
  also trusts the payee (the webhook's `payment.payee_trusted` is `false`).
  """

  alias Manza.Client

  @doc """
  Calls `POST /api/payments`.

  The draft is created with status `"requested"` and a `nil` `"transfer"`
  until it is authorized.

  Required attributes: `account_id`, `amount`, and exactly one of
  `beneficiary_id` (external transfer) or `destination_account_id`
  (own-account move).

  Optional attributes: `external_account_id`, `currency_code`,
  `payment_reference`, `internal_notes`, and `client_reference` (unique per
  entity, at most 128 characters; a duplicate returns
  `{:error, %Manza.Error{kind: :conflict}}` whose `payment_id` names the
  existing draft). The response carries `client_reference` and
  `authorization` (`%{"id", "status", "expires_at"}` or `nil`).
  """
  @spec create(Client.t(), map()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/payments", attributes)
  end

  @doc """
  Calls `GET /api/payments/:id`.

  Poll this to follow the draft through the in-app approval flow (status:
  `requested` → `processing` → `completed` / `failed`) — the API never
  executes a transfer itself.
  """
  @spec get(Client.t(), String.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/payments", id]))
  end

  @doc """
  Calls `POST /api/payments/:id/authorize`.

  Executes the draft. `authorization_id` comes from the
  `payment.authorization_requested` webhook; build `signature` with
  `Manza.TransferAuthorization`. Requires the `transfers:authorize` scope on a
  key other than the draft's creator (otherwise 403 `same_key_forbidden`),
  bound to an IP allowlist (otherwise 403 `unrestricted_api_key`). A 409
  `:conflict` with `type` `"authorization_busy"` means a bank-detail edit,
  trust or trust revocation on the payee was in flight: retry.

  A blank `signature` is refused locally with
  `{:error, %Manza.ConfigurationError{}}` before any HTTP call: the API counts
  it as a failed attempt, and five fail the challenge.
  """
  @spec authorize(Client.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def authorize(client, id, authorization_id, signature) do
    if blank?(signature) do
      {:error, %Manza.ConfigurationError{message: "signature cannot be blank"}}
    else
      Client.post(client, Client.encode_path(["api/payments", id, "authorize"]), %{
        "authorization_id" => authorization_id,
        "signature" => signature
      })
    end
  end

  @doc """
  Calls `POST /api/payments/:id/decline`.

  Declines the challenge and deletes the draft. Returns the authorization
  (`"status" => "declined"`, `"declined_at"`, and a `nil`
  `"refusal_reason"`). `reason` is omitted from the request when `nil`.
  """
  @spec decline(Client.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def decline(client, id, authorization_id, reason \\ nil) do
    body =
      if reason,
        do: %{"authorization_id" => authorization_id, "reason" => reason},
        else: %{"authorization_id" => authorization_id}

    Client.post(client, Client.encode_path(["api/payments", id, "decline"]), body)
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
