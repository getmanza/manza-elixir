defmodule Manza.TransferAuthorizationTest do
  # Fixed v2 test vectors, shared by every SDK in the family (same as
  # manza-ruby's spec/manza/transfer_authorization_spec.rb). The digests were
  # computed with:
  #
  #   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'

  use ExUnit.Case, async: true

  alias Manza.TransferAuthorization

  @secret "whsec_test_vector_secret"
  @payment_id "0199a1b2-0000-7000-8000-000000000001"
  @nonce "n0nce-0123456789abcdef"
  @account_id "0199a1b2-0000-7000-8000-000000000002"

  defp ext_payee,
    do:
      TransferAuthorization.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003")

  test "signs version v2" do
    input =
      TransferAuthorization.signature_input(
        @payment_id,
        @nonce,
        "2500.0",
        "MAD",
        @account_id,
        ext_payee(),
        "po_1",
        "eft"
      )

    assert String.starts_with?(input, "manza.transfer-authorization.v2|")
  end

  test "external-account payee with a client_reference and a transfer_method" do
    input =
      TransferAuthorization.signature_input(
        @payment_id,
        @nonce,
        "2500.0",
        "MAD",
        @account_id,
        ext_payee(),
        "po_1",
        "eft"
      )

    assert input ==
             "manza.transfer-authorization.v2|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" <>
               "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1|eft"

    assert TransferAuthorization.sign(@secret, input) ==
             "904da7d0b73b2c919ffa1ae64d262ce5825ee4d2c8420fd70a3d257353e6c43a"
  end

  test "a nil transfer_method ends with an empty segment" do
    input =
      TransferAuthorization.signature_input(
        @payment_id,
        @nonce,
        "2500.0",
        "MAD",
        @account_id,
        ext_payee(),
        "po_1",
        nil
      )

    assert String.ends_with?(input, "|ext:0199a1b2-0000-7000-8000-000000000003|po_1|")

    assert TransferAuthorization.sign(@secret, input) ==
             "029dd12924a846d7af2f4aecb61e4f4f9bd64d37315230864fb03917adc29edf"
  end

  test "own-account payee without a client_reference or a transfer_method ends with two empty segments" do
    payee =
      TransferAuthorization.payee_for(
        destination_account_id: "0199a1b2-0000-7000-8000-000000000004"
      )

    input =
      TransferAuthorization.signature_input(
        @payment_id,
        @nonce,
        "2500.0",
        "MAD",
        @account_id,
        payee,
        nil,
        nil
      )

    assert String.ends_with?(input, "|own:0199a1b2-0000-7000-8000-000000000004||")

    assert TransferAuthorization.sign(@secret, input) ==
             "a21ccf43b94f23d7a595a36bd788c27c7adbc5686a5ad4427b22d9957568c9fb"
  end

  test "signature_input refuses a non-string amount" do
    assert_raise ArgumentError, ~r/amount/, fn ->
      # apply/3 so the compiler's type checker doesn't flag the deliberate misuse
      apply(TransferAuthorization, :signature_input, [
        @payment_id,
        @nonce,
        2500,
        "MAD",
        @account_id,
        "ext:x",
        nil,
        nil
      ])
    end
  end

  # A v1 call (no transfer_method) fails here, not as a failed signature
  # attempt at the API, where five of them fail the challenge. A 1.x
  # seven-argument call must not become a v2 input that signs its
  # client_reference as the transfer_method.
  test "signature_input requires transfer_method and client_reference, nil included" do
    Code.ensure_loaded!(TransferAuthorization)

    assert function_exported?(TransferAuthorization, :signature_input, 8)
    refute function_exported?(TransferAuthorization, :signature_input, 7)
    refute function_exported?(TransferAuthorization, :signature_input, 6)
  end

  test "payee_for refuses both ids at once" do
    assert_raise ArgumentError, fn ->
      TransferAuthorization.payee_for(external_account_id: "a", destination_account_id: "b")
    end
  end

  test "payee_for refuses neither id" do
    assert_raise ArgumentError, fn -> TransferAuthorization.payee_for([]) end
  end
end
