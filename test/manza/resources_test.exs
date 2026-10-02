defmodule Manza.ResourcesTest do
  # Mirror of manza-go's resources_test.go (itself a mirror of manza-ruby's
  # spec/manza/resources/*_spec.rb) — same cassettes, same assertions, per the
  # cross-language SDK contract.

  use ExUnit.Case, async: true

  import Manza.Test.FixtureIDs, only: [fixture_id: 1]

  alias Manza.Test.CassetteReplay

  test "entity get" do
    client = CassetteReplay.replay_client(["entity/get"])

    assert {:ok, resp} = Manza.Entity.get(client)
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

    assert {:ok, page} = Manza.Accounts.list(client)
    assert page.data != []

    account_id = fixture_id("MANZA_FIXTURE_ACCOUNT_ID")
    assert {:ok, _resp} = Manza.Accounts.get(client, account_id)

    assert {:ok, _page} = Manza.Accounts.list_transactions(client, account_id)

    tx_id = fixture_id("MANZA_FIXTURE_TRANSACTION_ID")
    assert {:ok, _resp} = Manza.Accounts.get_transaction(client, account_id, tx_id)
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

    assert {:ok, _page} = Manza.Customers.list(client)

    customer_id = fixture_id("MANZA_FIXTURE_CUSTOMER_ID")
    assert {:ok, resp} = Manza.Customers.get(client, customer_id)
    assert is_binary(resp.body["id"])
  end

  test "invoices" do
    client = CassetteReplay.replay_client(["invoices/list", "invoices/get"])

    assert {:ok, page} = Manza.Invoices.list(client)
    assert page.data != []

    invoice_id = fixture_id("MANZA_FIXTURE_INVOICE_ID")
    assert {:ok, _resp} = Manza.Invoices.get(client, invoice_id)
  end

  test "payment links" do
    client =
      CassetteReplay.replay_client([
        "payment_links/list",
        "payment_links/get",
        "payment_links/create",
        "payment_links/cancel"
      ])

    assert {:ok, _page} = Manza.PaymentLinks.list(client)

    assert {:ok, resp} =
             Manza.PaymentLinks.create(client, %{
               "account_id" => fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
               "amount" => "100.00",
               "title" => "SDK fixture",
               "description" => "Created by zazu-ruby fixture spec",
               "link_type" => "single"
             })

    assert resp.status == 201

    assert {:ok, _resp} =
             Manza.PaymentLinks.cancel(
               client,
               fixture_id("MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID")
             )
  end

  test "checkout sessions" do
    client = CassetteReplay.replay_client(["checkout_sessions/get"])

    assert {:ok, resp} =
             Manza.CheckoutSessions.get(client, fixture_id("MANZA_FIXTURE_CHECKOUT_SESSION_ID"))

    assert is_binary(resp.body["id"])
  end

  test "webhook endpoints" do
    client = CassetteReplay.replay_client(["webhook_endpoints/list", "webhook_endpoints/get"])

    assert {:ok, _page} = Manza.WebhookEndpoints.list(client)

    assert {:ok, _resp} =
             Manza.WebhookEndpoints.get(client, fixture_id("MANZA_FIXTURE_WEBHOOK_ID"))
  end

  describe "transfer drafts" do
    test "create carries the client_reference" do
      client = CassetteReplay.replay_client(["transfer_drafts/create"])

      assert {:ok, resp} =
               Manza.TransferDrafts.create(client, %{
                 "account_id" => fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
                 "beneficiary_id" => fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
                 "amount" => "150.00",
                 "payment_reference" => "SDK fixture",
                 "client_reference" => fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE")
               })

      assert resp.status == 201
      # Awaiting approval — the API never executes a transfer itself.
      assert resp.body["status"] == "requested"
      assert resp.body["client_reference"] == fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE")
      assert Map.has_key?(resp.body, "authorization")
      assert resp.body["transfer"] == nil
    end

    test "create with a duplicate client_reference returns a conflict naming the draft" do
      client = CassetteReplay.replay_client(["transfer_drafts/create_duplicate"])

      assert {:error, %Manza.Error{} = error} =
               Manza.TransferDrafts.create(client, %{
                 "account_id" => fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
                 "beneficiary_id" => fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
                 "amount" => "10.00",
                 "client_reference" => fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
               })

      assert error.status == 409
      assert error.kind == :conflict
      assert error.type == "duplicate_client_reference"
      assert error.payment_id == fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID")
    end

    test "get" do
      client = CassetteReplay.replay_client(["transfer_drafts/get"])

      assert {:ok, got} =
               Manza.TransferDrafts.get(client, fixture_id("MANZA_FIXTURE_TRANSFER_DRAFT_ID"))

      assert is_binary(got.body["id"])
      assert Map.has_key?(got.body, "status")
      assert Map.has_key?(got.body, "transfer")
    end

    test "authorize refuses a blank signature without calling the API" do
      {:ok, client} = Manza.new(api_key: "test", base_url: "http://127.0.0.1:1")

      for blank <- ["", " ", nil] do
        assert {:error, %Manza.ConfigurationError{message: message}} =
                 Manza.TransferDrafts.authorize(client, "draft", "auth", blank)

        assert message =~ "signature"
      end
    end

    test "decline omits reason when absent" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/api/transfer_drafts/d1/decline", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"authorization_id" => "a1"}
        Plug.Conn.send_resp(conn, 200, ~s({"status":"declined"}))
      end)

      client = Manza.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")
      assert {:ok, _resp} = Manza.TransferDrafts.decline(client, "d1", "a1")
    end

    # Order matters while recording (five consecutive bad signatures suspend
    # the authorizer), not on replay. Each cassette loads on its own: the
    # authorize cassettes share method + URI.
    test "authorize with a bad signature is a validation error" do
      client =
        CassetteReplay.replay_client(["transfer_drafts/authorize_bad_signature"],
          ignore_signature: true
        )

      assert {:error, %Manza.Error{kind: :validation, type: "invalid_signature"}} =
               Manza.TransferDrafts.authorize(
                 client,
                 fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID"),
                 fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID"),
                 String.duplicate("0", 64)
               )
    end

    test "authorize with the creating key is forbidden" do
      client =
        CassetteReplay.replay_client(["transfer_drafts/authorize_same_key"],
          ignore_signature: true
        )

      assert {:error, %Manza.Error{kind: :forbidden, type: "same_key_forbidden"}} =
               Manza.TransferDrafts.authorize(
                 client,
                 fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"),
                 fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
                 String.duplicate("0", 64)
               )
    end

    test "authorize executes the draft" do
      client =
        CassetteReplay.replay_client(["transfer_drafts/authorize"], ignore_signature: true)

      draft_id = fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID")

      input =
        Manza.TransferAuthorization.signature_input(
          draft_id,
          fixture_id("MANZA_FIXTURE_AUTHORIZABLE_NONCE"),
          "10.0",
          "MAD",
          fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
          Manza.TransferAuthorization.payee_for(
            external_account_id: fixture_id("MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID")
          ),
          fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
        )

      # Replay strips `signature` before matching (it signs the real nonce
      # under the real secret), so this does not prove the signer; the
      # fixed vectors in transfer_authorization_test.exs do.
      signature = Manza.TransferAuthorization.sign("replay-secret", input)

      assert {:ok, resp} =
               Manza.TransferDrafts.authorize(
                 client,
                 draft_id,
                 fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
                 signature
               )

      assert resp.status == 200
      assert resp.body["id"] == draft_id
      assert resp.body["authorization"]["status"] == "authorized"
    end

    test "decline declines the challenge" do
      client = CassetteReplay.replay_client(["transfer_drafts/decline"])

      assert {:ok, resp} =
               Manza.TransferDrafts.decline(
                 client,
                 fixture_id("MANZA_FIXTURE_DECLINABLE_DRAFT_ID"),
                 fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"),
                 "SDK fixture"
               )

      assert resp.status == 200
      assert resp.body["id"] == fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID")
      assert resp.body["status"] == "declined"
      assert is_binary(resp.body["declined_at"])
    end
  end

  describe "beneficiaries" do
    test "list and get" do
      client = CassetteReplay.replay_client(["beneficiaries/list", "beneficiaries/get"])

      assert {:ok, page} = Manza.Beneficiaries.list(client)
      assert page.data != []
      assert is_list(hd(page.data)["external_accounts"])

      assert {:ok, resp} =
               Manza.Beneficiaries.get(client, fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"))

      assert is_binary(resp.body["id"])
      assert is_list(resp.body["external_accounts"])
    end

    test "create" do
      client = CassetteReplay.replay_client(["beneficiaries/create"])

      assert {:ok, resp} =
               Manza.Beneficiaries.create(client, %{
                 "beneficiary_type" => "business",
                 "company_name" => "Zazu Fixture Beneficiary - spec (zazu-ruby-fixture)",
                 "email" => "fixture-beneficiary-spec@example.com"
               })

      assert resp.status == 201
      assert resp.body["beneficiary_type"] == "business"
      assert resp.body["external_accounts"] == []
    end

    test "list_external_accounts returns a page of bank accounts" do
      client = CassetteReplay.replay_client(["beneficiaries/list_external_accounts"])

      assert {:ok, %Manza.Page{} = page} =
               Manza.Beneficiaries.list_external_accounts(
                 client,
                 fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID")
               )

      assert hd(page.data)["id"] == fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
      assert is_binary(hd(page.data)["account_number"])
    end

    test "get_external_account" do
      client = CassetteReplay.replay_client(["beneficiaries/get_external_account"])

      assert {:ok, resp} =
               Manza.Beneficiaries.get_external_account(
                 client,
                 fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
                 fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
               )

      assert resp.body["id"] == fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
      assert Map.has_key?(resp.body, "default")
    end

    test "create_external_account" do
      client = CassetteReplay.replay_client(["beneficiaries/create_external_account"])

      assert {:ok, resp} =
               Manza.Beneficiaries.create_external_account(
                 client,
                 fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
                 %{
                   "account_number" => fixture_id("MANZA_FIXTURE_NEW_ACCOUNT_NUMBER"),
                   "name" => "Fixture Secondary Account"
                 }
               )

      assert resp.status == 201
      assert resp.body["name"] == "Fixture Secondary Account"
      assert resp.body["default"] == false
    end
  end

  describe "payee trust requests" do
    test "create files a pending trust request" do
      client = CassetteReplay.replay_client(["payee_trust_requests/create"])
      ext_id = fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")

      assert {:ok, resp} = Manza.PayeeTrustRequests.create(client, [ext_id])
      assert resp.status == 201
      assert resp.body["status"] == "pending"
      assert resp.body["external_account_ids"] == [ext_id]
    end

    test "get" do
      client = CassetteReplay.replay_client(["payee_trust_requests/get"])
      id = fixture_id("MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID")

      assert {:ok, resp} = Manza.PayeeTrustRequests.get(client, id)
      assert resp.body["id"] == id
      assert resp.body["resolved_at"] == nil
    end
  end
end
