defmodule Zazu.TransferAuthorization do
  @moduledoc """
  Signs a machine-authorization challenge for an API-created transfer draft.
  Pure functions, no HTTP.

  The `payment.authorization_requested` webhook delivers the authorization id
  and a one-time nonce. Build the signature input from your *own* record of
  the transfer (not the webhook's `signature_input`, which is there only to
  compare against), sign it with the authorizer endpoint's signing secret,
  and pass the result to `Zazu.TransferDrafts.authorize/4`:

      input =
        Zazu.TransferAuthorization.signature_input(
          draft["id"],
          nonce,
          draft["amount"],
          draft["currency_code"],
          draft["account_id"],
          Zazu.TransferAuthorization.payee_for(external_account_id: draft["external_account_id"]),
          draft["client_reference"]
        )

      signature = Zazu.TransferAuthorization.sign(signing_secret, input)

      Zazu.TransferDrafts.authorize(client, draft["id"], authorization_id, signature)

  Argument errors raise `ArgumentError`: these are programming mistakes, not
  API outcomes.
  """

  @signature_version "manza.transfer-authorization.v1"

  @doc """
  Builds `manza.transfer-authorization.v1|<payment_id>|<nonce>|<amount>|<currency_code>|<account_id>|<payee>|<client_reference>`.

  `amount` must be the API's decimal string verbatim (e.g. `"2500.0"`).
  `client_reference` is empty when the transfer has none.
  """
  @spec signature_input(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil
        ) :: String.t()
  def signature_input(
        payment_id,
        nonce,
        amount,
        currency_code,
        account_id,
        payee,
        client_reference \\ nil
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
        client_reference || ""
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
