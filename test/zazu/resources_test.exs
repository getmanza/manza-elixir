defmodule Zazu.ResourcesTest do
  # Mirror of zazu-go's resources_test.go (itself a mirror of zazu-ruby's
  # spec/zazu/resources/*_spec.rb) — same cassettes, same assertions, per the
  # cross-language SDK contract.

  use ExUnit.Case, async: true

  import Zazu.Test.FixtureIDs, only: [fixture_id: 1]

  alias Zazu.Test.CassetteReplay

  test "entity get" do
    client = CassetteReplay.replay_client(["entity/get"])

    assert {:ok, resp} = Zazu.Entity.get(client)
    assert is_binary(resp.body["id"])
  end

  test "accounts" do
    client =
      CassetteReplay.replay_client([
        "accounts/list",
        "accounts/get",
        "accounts/list_transactions",
        "accounts/get_transaction"
      ])

    assert {:ok, page} = Zazu.Accounts.list(client)
    assert page.data != []

    account_id = fixture_id("ZAZU_FIXTURE_ACCOUNT_ID")
    assert {:ok, _resp} = Zazu.Accounts.get(client, account_id)

    assert {:ok, _page} = Zazu.Accounts.list_transactions(client, account_id)

    tx_id = fixture_id("ZAZU_FIXTURE_TRANSACTION_ID")
    assert {:ok, _resp} = Zazu.Accounts.get_transaction(client, account_id, tx_id)
  end

  test "customers" do
    client =
      CassetteReplay.replay_client([
        "customers/list",
        "customers/get",
        "customers/create",
        "customers/update",
        "customers/delete"
      ])

    assert {:ok, _page} = Zazu.Customers.list(client)

    customer_id = fixture_id("ZAZU_FIXTURE_CUSTOMER_ID")
    assert {:ok, resp} = Zazu.Customers.get(client, customer_id)
    assert is_binary(resp.body["id"])
  end

  test "invoices" do
    client = CassetteReplay.replay_client(["invoices/list", "invoices/get"])

    assert {:ok, page} = Zazu.Invoices.list(client)
    assert page.data != []

    invoice_id = fixture_id("ZAZU_FIXTURE_INVOICE_ID")
    assert {:ok, _resp} = Zazu.Invoices.get(client, invoice_id)
  end

  test "payment links" do
    client =
      CassetteReplay.replay_client([
        "payment_links/list",
        "payment_links/get",
        "payment_links/create",
        "payment_links/cancel"
      ])

    assert {:ok, _page} = Zazu.PaymentLinks.list(client)

    assert {:ok, resp} =
             Zazu.PaymentLinks.create(client, %{
               "account_id" => fixture_id("ZAZU_FIXTURE_ACCOUNT_ID"),
               "amount" => "100.00",
               "title" => "SDK fixture",
               "description" => "Created by zazu-ruby fixture spec",
               "link_type" => "single"
             })

    assert resp.status == 201

    assert {:ok, _resp} =
             Zazu.PaymentLinks.cancel(
               client,
               fixture_id("ZAZU_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID")
             )
  end

  test "checkout sessions" do
    client = CassetteReplay.replay_client(["checkout_sessions/get"])

    assert {:ok, resp} =
             Zazu.CheckoutSessions.get(client, fixture_id("ZAZU_FIXTURE_CHECKOUT_SESSION_ID"))

    assert is_binary(resp.body["id"])
  end

  test "webhook endpoints" do
    client = CassetteReplay.replay_client(["webhook_endpoints/list", "webhook_endpoints/get"])

    assert {:ok, _page} = Zazu.WebhookEndpoints.list(client)
    assert {:ok, _resp} = Zazu.WebhookEndpoints.get(client, fixture_id("ZAZU_FIXTURE_WEBHOOK_ID"))
  end

  test "transfer drafts" do
    client = CassetteReplay.replay_client(["transfer_drafts/create", "transfer_drafts/get"])

    assert {:ok, resp} =
             Zazu.TransferDrafts.create(client, %{
               "account_id" => fixture_id("ZAZU_FIXTURE_ACCOUNT_ID"),
               "beneficiary_id" => fixture_id("ZAZU_FIXTURE_BENEFICIARY_ID"),
               "amount" => "150.00",
               "payment_reference" => "SDK fixture"
             })

    assert resp.status == 201
    # Awaiting in-app approval — the API never executes a transfer itself.
    assert resp.body["status"] == "requested"
    assert resp.body["transfer"] == nil

    assert {:ok, got} =
             Zazu.TransferDrafts.get(client, fixture_id("ZAZU_FIXTURE_TRANSFER_DRAFT_ID"))

    assert is_binary(got.body["status"])
  end

  test "beneficiaries" do
    client = CassetteReplay.replay_client(["beneficiaries/list", "beneficiaries/get"])

    assert {:ok, page} = Zazu.Beneficiaries.list(client)
    assert page.data != []
    assert is_list(hd(page.data)["external_accounts"])

    assert {:ok, resp} = Zazu.Beneficiaries.get(client, fixture_id("ZAZU_FIXTURE_BENEFICIARY_ID"))
    assert is_binary(resp.body["id"])
  end
end
