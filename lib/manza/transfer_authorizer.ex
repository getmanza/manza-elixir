defmodule Manza.TransferAuthorizer do
  @moduledoc """
  The entity's enrolled transfer authorizer, read-only. Enrolment, limits, the
  "Approve transfers to new payees" option and resume stay in the app behind
  a second factor. A singular resource: no list, no id.
  """

  alias Manza.Client

  @doc """
  Calls `GET /api/transfer_authorizer`.

  Any key with `transfers:read`, `transfers:write` or `transfers:authorize`.
  The body carries `status` (`"active"` / `"suspended"`), `suspension_reason`
  (`"member"`, `"signature_failures"`, `"secret_expired"`,
  `"endpoint_disabled"`; `nil` when active), `currency_code`,
  `per_transfer_limit`, `daily_limit`, `daily_authorized_total` (the last 24
  hours), `secret_expires_at`, `webhook_endpoint_id`, `enrolled_at`,
  `trust_new_payees` (whether "Approve transfers to new payees" is on) and
  `new_payee_limit` (the ceiling for a transfer to a new payee, a decimal
  string; `nil` while `trust_new_payees` is off).

  Returns `{:error, %Manza.Error{kind: :not_found}}` when no authorizer is
  enrolled.
  """
  @spec get(Client.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client) do
    Client.get(client, "api/transfer_authorizer")
  end
end
