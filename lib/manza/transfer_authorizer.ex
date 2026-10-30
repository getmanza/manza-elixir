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
  hours), `secret_expires_at`, `webhook_endpoint_id` and `enrolled_at`. It
  does not show whether new payees are approved.

  Returns `{:error, %Manza.Error{kind: :not_found}}` when no authorizer is
  enrolled.
  """
  @spec get(Client.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client) do
    Client.get(client, "api/transfer_authorizer")
  end
end
