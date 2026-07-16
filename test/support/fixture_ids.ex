defmodule Zazu.Test.FixtureIDs do
  @moduledoc """
  Mirror of `spec/support/fixture_ids.rb` in zazu-ruby. The placeholders must
  exactly match what VCR scrubbed the real staging UUIDs to when the
  cassettes were recorded — otherwise the request URI won't match.
  """

  @fixture_ids %{
    "ZAZU_FIXTURE_ACCOUNT_ID" => "fixture-account-id",
    "ZAZU_FIXTURE_TRANSACTION_ID" => "fixture-transaction-id",
    "ZAZU_FIXTURE_CUSTOMER_ID" => "fixture-customer-id",
    "ZAZU_FIXTURE_DELETABLE_CUSTOMER_ID" => "fixture-deletable-customer-id",
    "ZAZU_FIXTURE_INVOICE_ID" => "fixture-invoice-id",
    "ZAZU_FIXTURE_DELETABLE_INVOICE_ID" => "fixture-deletable-invoice-id",
    "ZAZU_FIXTURE_PAYMENT_LINK_ID" => "fixture-payment-link-id",
    "ZAZU_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID" => "fixture-cancellable-payment-link-id",
    "ZAZU_FIXTURE_WEBHOOK_ID" => "fixture-webhook-id",
    "ZAZU_FIXTURE_ENABLED_WEBHOOK_ID" => "fixture-enabled-webhook-id",
    "ZAZU_FIXTURE_DISABLED_WEBHOOK_ID" => "fixture-disabled-webhook-id",
    "ZAZU_FIXTURE_DELETABLE_WEBHOOK_ID" => "fixture-deletable-webhook-id",
    "ZAZU_FIXTURE_CHECKOUT_SESSION_ID" => "fixture-checkout-session-id",
    "ZAZU_FIXTURE_BENEFICIARY_ID" => "fixture-beneficiary-id",
    "ZAZU_FIXTURE_TRANSFER_DRAFT_ID" => "fixture-transfer-draft-id"
  }

  @doc "Looks up a fixture placeholder id. Raises on an unknown env var name."
  def fixture_id(env_var) do
    case Map.fetch(@fixture_ids, env_var) do
      {:ok, placeholder} ->
        placeholder

      :error ->
        raise KeyError, "unknown fixture env var #{inspect(env_var)} — add it to @fixture_ids"
    end
  end
end
