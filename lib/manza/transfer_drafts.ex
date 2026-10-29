defmodule Manza.TransferDrafts do
  @moduledoc """
  Deprecated alias of `Manza.Payments`, kept for all of 1.x.

  Every function delegates to `Manza.Payments`, so it calls `/api/payments`.
  The deprecation is soft: it shows in the docs and emits no compile warning.
  """
  @moduledoc deprecated: "Use Manza.Payments"

  @doc deprecated: "Use Manza.Payments.create/2"
  @doc "Same as `Manza.Payments.create/2`."
  defdelegate create(client, attributes), to: Manza.Payments

  @doc deprecated: "Use Manza.Payments.get/2"
  @doc "Same as `Manza.Payments.get/2`."
  defdelegate get(client, id), to: Manza.Payments

  @doc deprecated: "Use Manza.Payments.authorize/4"
  @doc "Same as `Manza.Payments.authorize/4`."
  defdelegate authorize(client, id, authorization_id, signature), to: Manza.Payments

  @doc deprecated: "Use Manza.Payments.decline/4"
  @doc "Same as `Manza.Payments.decline/4`."
  defdelegate decline(client, id, authorization_id, reason \\ nil), to: Manza.Payments
end
