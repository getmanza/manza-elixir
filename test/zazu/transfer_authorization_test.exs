defmodule Zazu.TransferAuthorizationTest do
  # Fixed test vector, shared by every SDK in the family (same as zazu-ruby's
  # spec/zazu/transfer_authorization_spec.rb). The digests were computed with:
  #
  #   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'

  use ExUnit.Case, async: true

  alias Zazu.TransferAuthorization

  @secret "whsec_test_vector_secret"
  @payment_id "0199a1b2-0000-7000-8000-000000000001"
  @nonce "n0nce-0123456789abcdef"
  @account_id "0199a1b2-0000-7000-8000-000000000002"

  test "external-account payee with a client_reference" do
    payee =
      TransferAuthorization.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003")

    input =
      TransferAuthorization.signature_input(
        @payment_id,
        @nonce,
        "2500.0",
        "MAD",
        @account_id,
        payee,
        "po_1"
      )

    assert input ==
             "manza.transfer-authorization.v1|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" <>
               "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1"

    assert TransferAuthorization.sign(@secret, input) ==
             "6e8eaec0f89a4eb3b22df1133b3d6dfebfa8505c34c58ed0ff192516e4223078"
  end

  test "own-account payee without a client_reference ends with an empty segment" do
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
        payee
      )

    assert String.ends_with?(input, "|own:0199a1b2-0000-7000-8000-000000000004|")

    assert TransferAuthorization.sign(@secret, input) ==
             "af9440b1de1bebb51f381ce43e3d0d27b6a4ccb99dcd548c0b5435ff4fdd1895"
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
        "ext:x"
      ])
    end
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
