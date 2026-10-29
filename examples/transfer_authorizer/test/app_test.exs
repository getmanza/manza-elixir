defmodule TransferAuthorizer.AppTest do
  # Drives the example's authorizer with a signed copy of the documented
  # `payment.authorization_requested` payload (the same one manza-ruby's
  # spec/examples/transfer_authorizer_spec.rb uses). The API is a Bypass
  # server: no cassette, no network.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias TransferAuthorizer.{App, Ledger}

  @secret "whsec_example_authorizer_secret"
  @draft_id "01958e51-7c5a-7000-8000-000000000012"
  @authorization_id "01958e51-7c5a-7000-8000-000000000011"
  @payee "ext:01958e51-7c5a-7000-8000-000000000014"
  @signature_input "manza.transfer-authorization.v1|01958e51-7c5a-7000-8000-000000000012|" <>
                     "9f86d081884c7d659a2feaa0c55ad015|2500.0|ZAR|01958e51-7c5a-7000-8000-000000000013|" <>
                     "ext:01958e51-7c5a-7000-8000-000000000014|po_8812"
  @payload %{
    "event" => "payment.authorization_requested",
    "event_id" => "01958e51-7c5a-7000-8000-000000000010",
    "created_at" => "2026-10-01T12:00:00Z",
    "data" => %{
      "authorization" => %{
        "id" => "01958e51-7c5a-7000-8000-000000000011",
        "nonce" => "9f86d081884c7d659a2feaa0c55ad015",
        "expires_at" => "2026-10-01T13:00:00Z",
        "signature_version" => "manza.transfer-authorization.v1"
      },
      "payment" => %{
        "id" => "01958e51-7c5a-7000-8000-000000000012",
        "amount" => "2500.0",
        "currency_code" => "ZAR",
        "account_id" => "01958e51-7c5a-7000-8000-000000000013",
        "payee" => "ext:01958e51-7c5a-7000-8000-000000000014",
        "beneficiary_id" => "01958e51-7c5a-7000-8000-000000000015",
        "external_account_id" => "01958e51-7c5a-7000-8000-000000000014",
        "destination_account_id" => nil,
        "payment_reference" => "INV-2026-001",
        "client_reference" => "po_8812",
        "payee_trusted" => false
      },
      "signature_input" =>
        "manza.transfer-authorization.v1|01958e51-7c5a-7000-8000-000000000012|" <>
          "9f86d081884c7d659a2feaa0c55ad015|2500.0|ZAR|01958e51-7c5a-7000-8000-000000000013|" <>
          "ext:01958e51-7c5a-7000-8000-000000000014|po_8812"
    }
  }
  @entry %{
    "payment_id" => "01958e51-7c5a-7000-8000-000000000012",
    "amount" => "2500.0",
    "currency_code" => "ZAR",
    "account_id" => "01958e51-7c5a-7000-8000-000000000013",
    "payee" => "ext:01958e51-7c5a-7000-8000-000000000014"
  }

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    bypass = Bypass.open()
    ledger = Path.join(dir, "ledger.json")

    %{
      bypass: bypass,
      ledger: ledger,
      opts: [
        client: Manza.new!(api_key: "key-b", base_url: "http://localhost:#{bypass.port}"),
        secret: @secret,
        ledger: ledger,
        executor: fn job -> job.() end,
        ledger_wait: 0,
        retry_delay: 0
      ]
    }
  end

  defp deliver(opts, body, signature \\ nil) do
    timestamp = Integer.to_string(System.system_time(:second))
    signature = signature || Manza.Webhook.sign(body, timestamp, @secret)

    conn(:post, "/", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-manza-signature", signature)
    |> put_req_header("x-manza-timestamp", timestamp)
    |> App.call(App.init(opts))
  end

  defp payload(changes) do
    Enum.reduce(changes, @payload, fn {path, value}, acc -> put_in(acc, path, value) end)
  end

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  # Answers each call with the next response from `responses` and counts them.
  defp expect_calls(bypass, path, responses) do
    {:ok, agent} = Agent.start_link(fn -> {0, []} end)

    Bypass.expect(bypass, "POST", path, fn conn ->
      {:ok, raw, conn} = read_body(conn)

      n =
        Agent.get_and_update(agent, fn {n, bodies} ->
          {n, {n + 1, bodies ++ [{get_req_header(conn, "authorization"), Jason.decode!(raw)}]}}
        end)

      {status, body} = Enum.at(responses, n, List.last(responses))
      json(conn, status, body)
    end)

    agent
  end

  defp calls(agent), do: agent |> Agent.get(& &1) |> elem(1)

  defp expected_signature do
    Manza.TransferAuthorization.sign(@secret, @signature_input)
  end

  describe "with a matching ledger entry" do
    setup %{ledger: ledger} do
      Ledger.record(ledger, "po_8812", @entry)
      :ok
    end

    test "signs from the ledger and authorizes with key B", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {200, %{"id" => @draft_id, "status" => "processing"}}
        ])

      log = capture_log(fn -> assert deliver(opts, Jason.encode!(@payload)).status == 200 end)

      assert calls(agent) == [
               {["Bearer key-b"],
                %{"authorization_id" => @authorization_id, "signature" => expected_signature()}}
             ]

      for line <- [
            "signature verified",
            "ledger match",
            "signed the challenge",
            "authorized payment"
          ] do
        assert log =~ line
      end

      assert log =~ ~s(status "processing")
    end

    test "logs the API error type and request id when authorize fails", %{
      bypass: bypass,
      opts: opts
    } do
      Bypass.expect(bypass, "POST", "/api/payments/#{@draft_id}/authorize", fn conn ->
        conn
        |> put_resp_header("x-request-id", "req_123")
        |> json(422, %{
          "error" => %{"message" => "Signature does not match", "type" => "invalid_signature"}
        })
      end)

      log = capture_log(fn -> assert deliver(opts, Jason.encode!(@payload)).status == 200 end)

      assert log =~ "API error"
      assert log =~ "invalid_signature"
      assert log =~ "req_123"
    end

    test "logs both signature inputs and does not authorize when the webhook's differs", %{
      opts: opts
    } do
      body = Jason.encode!(payload([{["data", "signature_input"], "something-else"}]))

      log = capture_log(fn -> deliver(opts, body) end)

      assert log =~ "something-else"
      assert log =~ @signature_input
    end

    test "retries authorize after a transient failure", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {503, %{}},
          {200, %{"status" => "processing"}}
        ])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert length(calls(agent)) == 2
      assert log =~ "retrying"
      assert log =~ "authorized payment"
    end

    test "gives up after three attempts", %{bypass: bypass, opts: opts} do
      agent = expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [{503, %{}}])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert length(calls(agent)) == 3
      assert log =~ "API error server"
    end

    test "retries authorize while the API answers authorization_busy", %{
      bypass: bypass,
      opts: opts
    } do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {409, %{"error" => %{"type" => "authorization_busy"}}},
          {200, %{"status" => "processing"}}
        ])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert length(calls(agent)) == 2
      assert log =~ "retrying"
      assert log =~ "authorized payment"
    end

    test "does not retry another conflict", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {409, %{"error" => %{"type" => "already_answered"}}}
        ])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert length(calls(agent)) == 1
      assert log =~ "API error conflict"
    end

    test "does not retry a validation error", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {422, %{"error" => %{"type" => "invalid_signature"}}}
        ])

      capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert length(calls(agent)) == 1
    end

    test "logs that a new payee will be trusted on authorize", %{bypass: bypass, opts: opts} do
      expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
        {200, %{"status" => "processing"}}
      ])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert log =~ "new payee #{@payee}, will be trusted on authorize"
    end

    test "does not log a new payee when the payee is already trusted", %{
      bypass: bypass,
      opts: opts
    } do
      expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
        {200, %{"status" => "processing"}}
      ])

      body = Jason.encode!(payload([{["data", "payment", "payee_trusted"], true}]))

      log = capture_log(fn -> deliver(opts, body) end)

      refute log =~ "new payee"
    end
  end

  describe "with ALLOW_NEW_PAYEES=false" do
    setup %{ledger: ledger, opts: opts} do
      Ledger.record(ledger, "po_8812", @entry)
      %{opts: Keyword.put(opts, :allow_new_payees, false)}
    end

    test "declines a transfer to a payee that is not trusted yet", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/decline", [
          {200, %{"id" => @authorization_id, "status" => "declined"}}
        ])

      log = capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert [{_, %{"authorization_id" => @authorization_id, "reason" => reason}}] = calls(agent)
      assert reason =~ "new payee"
      assert log =~ "declined payment"
    end

    test "declines a webhook that does not say whether the payee is trusted", %{
      bypass: bypass,
      opts: opts
    } do
      agent = expect_calls(bypass, "/api/payments/#{@draft_id}/decline", [{200, %{}}])

      body =
        Jason.encode!(update_in(@payload, ["data", "payment"], &Map.delete(&1, "payee_trusted")))

      capture_log(fn -> deliver(opts, body) end)

      assert [{_, %{"reason" => reason}}] = calls(agent)
      assert reason =~ "new payee"
    end

    test "authorizes a trusted payee", %{bypass: bypass, opts: opts} do
      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/authorize", [
          {200, %{"status" => "processing"}}
        ])

      body = Jason.encode!(payload([{["data", "payment", "payee_trusted"], true}]))

      capture_log(fn -> deliver(opts, body) end)

      assert length(calls(agent)) == 1
    end
  end

  describe "with a ledger mismatch" do
    test "declines with a reason naming the field", %{bypass: bypass, ledger: ledger, opts: opts} do
      Ledger.record(ledger, "po_8812", Map.put(@entry, "amount", "25000.0"))

      agent =
        expect_calls(bypass, "/api/payments/#{@draft_id}/decline", [
          {200, %{"id" => @authorization_id, "status" => "declined"}}
        ])

      log = capture_log(fn -> assert deliver(opts, Jason.encode!(@payload)).status == 200 end)

      assert [{_, %{"authorization_id" => @authorization_id, "reason" => reason}}] = calls(agent)
      assert reason =~ "amount"
      assert log =~ "declined payment"
    end
  end

  describe "without a ledger entry" do
    test "declines a client_reference this authorizer never issued", %{bypass: bypass, opts: opts} do
      agent = expect_calls(bypass, "/api/payments/#{@draft_id}/decline", [{200, %{}}])

      capture_log(fn -> deliver(opts, Jason.encode!(@payload)) end)

      assert [{_, %{"reason" => reason}}] = calls(agent)
      assert reason =~ "po_8812"
    end
  end

  # No Bypass expectation in these: any API call fails the test.
  describe "with a bad signature" do
    test "answers 401 and calls nothing", %{opts: opts} do
      log =
        capture_log(fn ->
          conn = deliver(opts, Jason.encode!(@payload), String.duplicate("0", 64))
          assert conn.status == 401
          # The body manza-ruby's example answers.
          assert conn.resp_body == "unauthorized"
        end)

      assert log =~ "rejected a delivery: invalid webhook signature"
    end
  end

  describe "with a signed body that is not a JSON object" do
    test "answers 401 and calls nothing", %{opts: opts} do
      capture_log(fn -> assert deliver(opts, "[]").status == 401 end)
    end
  end

  describe "with a body over the read limit" do
    test "answers 413 and calls nothing", %{opts: opts} do
      body = String.duplicate("a", 9_000_000)

      log = capture_log(fn -> assert deliver(opts, body).status == 413 end)

      assert log =~ "rejected a delivery"
    end
  end

  describe "with another event" do
    test "answers 200 and calls nothing", %{opts: opts} do
      body =
        Jason.encode!(%{
          "event" => "test.ping",
          "event_id" => "0199a1b2-0000-7000-8000-000000000010"
        })

      log = capture_log(fn -> assert deliver(opts, body).status == 200 end)

      assert log =~ "ignoring test.ping"
    end
  end
end
