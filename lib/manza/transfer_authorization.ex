defmodule Manza.TransferAuthorization do
  @moduledoc """
  Signs a machine-authorization challenge for an API-created transfer draft.
  Pure functions, no HTTP.

  The `payment.authorization_requested` webhook delivers the authorization id
  and a one-time nonce. Build the signature input from your *own* record of
  the transfer (not the webhook's `signature_input_v2`, which is there only to
  compare against), sign it with the authorizer endpoint's signing secret,
  and pass the result to `Manza.Payments.authorize/4`:

      input =
        Manza.TransferAuthorization.signature_input(
          draft["id"],
          nonce,
          draft["amount"],
          draft["currency_code"],
          draft["account_id"],
          Manza.TransferAuthorization.payee_for(external_account_id: draft["external_account_id"]),
          draft["client_reference"],
          draft["transfer_method"]
        )

      signature = Manza.TransferAuthorization.sign(signing_secret, input)

      Manza.Payments.authorize(client, draft["id"], authorization_id, signature)

  This is the v2 input, which the API verifies for every request that is
  unpinned or sends `Manza-Version: 2026-11-13` or later. A client pinned to
  `Manza-Version: 2026-03-27` must sign v1 and stays on manza 1.x.

  Argument errors raise `ArgumentError`: these are programming mistakes, not
  API outcomes.
  """

  @signature_version "manza.transfer-authorization.v2"

  @doc """
  Builds `manza.transfer-authorization.v2|<payment_id>|<nonce>|<amount>|<currency_code>|<account_id>|<payee>|<client_reference>|<transfer_method>`.

  `amount` must be the API's decimal string verbatim (e.g. `"2500.0"`).
  `client_reference` is signed as an empty segment when the transfer has none
  (`nil`). `transfer_method` is the payment's rail as the API stores it (the
  create response's `"transfer_method"`), signed as an empty segment when it
  is `nil` (a market with no rail choice). Both are required arguments, `nil`
  included: a 1.x seven-argument call warns at compile time and raises
  `UndefinedFunctionError` before any request, instead of signing its
  `client_reference` as the `transfer_method`.
  """
  @spec signature_input(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil
        ) :: String.t()
  def signature_input(
        payment_id,
        nonce,
        amount,
        currency_code,
        account_id,
        payee,
        client_reference,
        transfer_method
      ) do
    unless is_binary(amount) do
      raise ArgumentError, "amount must be the API's decimal string (got #{inspect(amount)})"
    end

    Enum.join(
      [
        @signature_version,
        payment_id,
        nonce,
        amount,
        currency_code,
        account_id,
        payee,
        client_reference || "",
        transfer_method || ""
      ],
      "|"
    )
  end

  @doc "Lowercase hex HMAC-SHA256 of the signature input under the authorizer endpoint's signing secret."
  @spec sign(String.t(), String.t()) :: String.t()
  def sign(secret, signature_input) do
    :hmac
    |> :crypto.mac(:sha256, secret, signature_input)
    |> Base.encode16(case: :lower)
  end

  @doc """
  The payee token: `ext:<id>` for a beneficiary's bank account (`:external_account_id`),
  `own:<id>` for one of the entity's own accounts (`:destination_account_id`).
  Pass exactly one.
  """
  @spec payee_for(keyword()) :: String.t()
  def payee_for(opts) do
    case {opts[:external_account_id], opts[:destination_account_id]} do
      {ext, nil} when is_binary(ext) ->
        "ext:" <> ext

      {nil, own} when is_binary(own) ->
        "own:" <> own

      _ ->
        raise ArgumentError, "pass exactly one of external_account_id or destination_account_id"
    end
  end
end
