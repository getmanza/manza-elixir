defmodule TransferAuthorizer.PreflightTest do
  # Drives the example's preflight against a Bypass server answering the
  # documented responses. No cassette, no network: each failure is a stubbed
  # response.
  use ExUnit.Case, async: true

  import Plug.Conn

  alias TransferAuthorizer.Preflight

  @account_id "01958e51-7c5a-7000-8000-000000000013"
  @beneficiary_id "01958e51-7c5a-7000-8000-000000000015"
  @endpoint_id "01958e51-7c5a-7000-8000-000000000020"
  @now ~U[2026-10-20 12:00:00Z]

  @authorizer %{
    "status" => "active",
    "suspension_reason" => nil,
    "currency_code" => "MAD",
    "per_transfer_limit" => "1000.0",
    "daily_limit" => "5000.0",
    "daily_authorized_total" => "100.0",
    "secret_expires_at" => "2027-01-18T00:00:00Z",
    "webhook_endpoint_id" => @endpoint_id,
    "enrolled_at" => "2026-10-01T08:30:00Z"
  }
  @endpoint %{
    "id" => @endpoint_id,
    "url" => "https://authorizer.example.com/",
    "status" => "active"
  }
  @payee %{"id" => "01958e51-7c5a-7000-8000-000000000014", "default" => true, "trusted" => true}

  setup do
    bypass = Bypass.open()

    env = %{
      "MANZA_BASE_URL" => "http://localhost:#{bypass.port}",
      "MANZA_CREATOR_API_KEY" => "key-a",
      "MANZA_AUTHORIZER_API_KEY" => "key-b",
      "MANZA_AUTHORIZER_SECRET" => "whsec_example",
      "MANZA_ACCOUNT_ID" => @account_id,
      "MANZA_BENEFICIARY_ID" => @beneficiary_id
    }

    %{bypass: bypass, env: env}
  end

  # Serves the API; `overrides` maps a path to `{status, body}`.
  defp serve(bypass, overrides \\ %{}) do
    routes = %{
      "/api/entity" => {"key-a", {200, %{"id" => "e1", "name" => "Acme"}}},
      "/api/transfer_authorizer" => {"key-b", {200, @authorizer}},
      "/api/accounts/#{@account_id}" =>
        {"key-a", {200, %{"id" => @account_id, "currency_code" => "MAD"}}},
      "/api/webhook_endpoints/#{@endpoint_id}" => {"key-a", {200, @endpoint}},
      "/api/beneficiaries/#{@beneficiary_id}" =>
        {"key-a", {200, %{"id" => @beneficiary_id, "external_accounts" => [@payee]}}}
    }

    for {path, {key, default}} <- routes do
      Bypass.stub(bypass, "GET", path, fn conn ->
        assert get_req_header(conn, "authorization") == ["Bearer #{key}"]
        {status, body} = Map.get(overrides, path, default)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode!(body))
      end)
    end
  end

  defp error(status, type), do: {status, %{"error" => %{"type" => type, "message" => "refused"}}}

  defp run(env, amount \\ "10.00") do
    {:ok, out} = StringIO.open("")
    ok = Preflight.run(env: env, amount: amount, out: out, now: @now)
    {:ok, {_, output}} = StringIO.close(out)
    {ok, output}
  end

  defp lines(output, mark),
    do: output |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, mark))

  defp failures(output), do: lines(output, "✗")

  test "passes every step when the setup is complete", %{bypass: bypass, env: env} do
    serve(bypass)
    {ok, output} = run(env)

    assert ok
    assert failures(output) == []
    assert length(lines(output, "✓")) == 9
  end

  # No Bypass route in these: any request fails the test.
  test "fails when a key is missing, before any request", %{env: env} do
    {ok, output} = run(Map.put(env, "MANZA_AUTHORIZER_API_KEY", ""))

    refute ok
    assert hd(failures(output)) =~ "MANZA_AUTHORIZER_API_KEY"
  end

  test "fails when the beneficiary id is missing, before any request", %{env: env} do
    {ok, output} = run(Map.put(env, "MANZA_BENEFICIARY_ID", ""))

    refute ok
    assert hd(failures(output)) =~ "MANZA_BENEFICIARY_ID"
  end

  test "stops before any request on a missing key, even with a bad amount", %{env: env} do
    {_, output} = run(Map.put(env, "MANZA_CREATOR_API_KEY", ""), "0")

    assert length(failures(output)) == 2
  end

  test "fails when both keys are the same", %{env: env} do
    {_, output} = run(Map.put(env, "MANZA_AUTHORIZER_API_KEY", "key-a"))

    assert hd(failures(output)) =~ "different"
  end

  test "fails when the amount is not a decimal, and runs the other checks", %{
    bypass: bypass,
    env: env
  } do
    serve(bypass)
    {ok, output} = run(env, "ten")

    refute ok
    assert [failure] = failures(output)
    assert failure =~ ~s("ten")
    assert failure =~ "10.00"
    assert output =~ "✓ transfer authorizer is active"
    refute output =~ "limit per transfer and"
  end

  test "fails when the amount is not positive", %{bypass: bypass, env: env} do
    serve(bypass)

    for amount <- ["-5", "0", "1/2", "1e2"] do
      {_, output} = run(env, amount)

      assert hd(failures(output)) =~ inspect(amount)
      assert hd(failures(output)) =~ "positive"
    end
  end

  test "fails when key A cannot reach the entity", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/entity" => error(401, "authentication_error")})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "key A"
    assert hd(failures(output)) =~ "MANZA_CREATOR_API_KEY"
  end

  test "fails when no authorizer is enrolled", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/transfer_authorizer" => error(404, "not_found_error")})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "no transfer authorizer is enrolled"
    assert hd(failures(output)) =~ "Transfer approval"
  end

  test "fails when key B cannot read the authorizer", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/transfer_authorizer" => error(403, "insufficient_scope")})
    {_, output} = run(env)

    for part <- ["key B", "insufficient_scope", "transfers:authorize"],
        do: assert(hd(failures(output)) =~ part)
  end

  test "fails with the suspension reason and its fix", %{bypass: bypass, env: env} do
    authorizer = %{
      @authorizer
      | "status" => "suspended",
        "suspension_reason" => "endpoint_disabled"
    }

    serve(bypass, %{"/api/transfer_authorizer" => {200, authorizer}})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "suspended (endpoint_disabled)"
    assert hd(failures(output)) =~ "re-enable"
  end

  test "fails once, on the authorizer line, when the secret has expired", %{
    bypass: bypass,
    env: env
  } do
    authorizer = %{
      @authorizer
      | "status" => "suspended",
        "suspension_reason" => "secret_expired",
        "secret_expires_at" => "2026-10-19T00:00:00Z"
    }

    serve(bypass, %{"/api/transfer_authorizer" => {200, authorizer}})
    {_, output} = run(env)

    assert [failure] = failures(output)
    assert failure =~ "suspended (secret_expired)"
    assert failure =~ "rotates the secret"
  end

  test "fails when key A cannot read the account", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/accounts/#{@account_id}" => error(403, "insufficient_scope")})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "key A"
    assert hd(failures(output)) =~ "accounts:read"
  end

  test "fails when key A cannot read the enrolled webhook endpoint", %{bypass: bypass, env: env} do
    serve(bypass, %{
      "/api/webhook_endpoints/#{@endpoint_id}" => error(403, "insufficient_scope")
    })

    {_, output} = run(env)

    assert hd(failures(output)) =~ "key A"
    assert hd(failures(output)) =~ "webhook_endpoints:read"
  end

  test "fails when the account's currency is not the enrolled one", %{bypass: bypass, env: env} do
    serve(bypass, %{
      "/api/accounts/#{@account_id}" => {200, %{"id" => @account_id, "currency_code" => "ZAR"}}
    })

    {_, output} = run(env)

    assert hd(failures(output)) =~ "ZAR"
    assert hd(failures(output)) =~ "MAD"
  end

  test "fails when the secret expires within 7 days", %{bypass: bypass, env: env} do
    serve(bypass, %{
      "/api/transfer_authorizer" =>
        {200, %{@authorizer | "secret_expires_at" => "2026-10-23T00:00:00Z"}}
    })

    {_, output} = run(env)

    assert hd(failures(output)) =~ "secret expires in 2 days"
    assert hd(failures(output)) =~ "rotate"
  end

  test "fails when the signing secret is not set", %{bypass: bypass, env: env} do
    serve(bypass)
    {_, output} = run(Map.put(env, "MANZA_AUTHORIZER_SECRET", ""))

    assert hd(failures(output)) =~ "MANZA_AUTHORIZER_SECRET"
  end

  test "fails when the enrolled webhook endpoint is disabled", %{bypass: bypass, env: env} do
    serve(bypass, %{
      "/api/webhook_endpoints/#{@endpoint_id}" => {200, %{@endpoint | "status" => "disabled"}}
    })

    {_, output} = run(env)

    for part <- ["disabled", "enable", "if the authorizer stays suspended"],
        do: assert(hd(failures(output)) =~ part)
  end

  test "fails when the enrolled webhook endpoint was deleted", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/webhook_endpoints/#{@endpoint_id}" => error(404, "not_found_error")})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "was deleted"
    assert hd(failures(output)) =~ "enrol"
  end

  test "warns when the endpoint is on a URL that changes when the tunnel restarts", %{
    bypass: bypass,
    env: env
  } do
    serve(bypass, %{
      "/api/webhook_endpoints/#{@endpoint_id}" =>
        {200, %{@endpoint | "url" => "https://abc123.ngrok-free.app/"}}
    })

    {ok, output} = run(env)

    assert ok
    assert hd(lines(output, "!")) =~ "ngrok-free.app"
    assert hd(lines(output, "!")) =~ "reserved domain"
  end

  test "fails when the amount is over the limit per transfer", %{bypass: bypass, env: env} do
    serve(bypass)
    {_, output} = run(env, "1500.00")

    assert hd(failures(output)) =~ "1500.00 is over the limit per transfer (1000.00)"
  end

  test "fails when the amount does not fit in the last 24 hours' room", %{
    bypass: bypass,
    env: env
  } do
    serve(bypass, %{
      "/api/transfer_authorizer" => {200, %{@authorizer | "daily_authorized_total" => "4995.0"}}
    })

    {_, output} = run(env)

    assert hd(failures(output)) =~ "24 hours' room (5.00 left)"
  end

  test "warns that a new payee needs the toggle, which the API does not show", %{
    bypass: bypass,
    env: env
  } do
    serve(bypass, %{
      "/api/beneficiaries/#{@beneficiary_id}" =>
        {200, %{"id" => @beneficiary_id, "external_accounts" => [%{@payee | "trusted" => false}]}}
    })

    {ok, output} = run(env)

    assert ok

    for part <- ["not trusted yet", "Approve transfers to new payees", "IP allowlist"],
        do: assert(hd(lines(output, "!")) =~ part)
  end

  test "fails when the beneficiary has no default bank account", %{bypass: bypass, env: env} do
    serve(bypass, %{
      "/api/beneficiaries/#{@beneficiary_id}" =>
        {200, %{"id" => @beneficiary_id, "external_accounts" => [%{@payee | "default" => false}]}}
    })

    {_, output} = run(env)

    assert hd(failures(output)) =~ "default bank account"
  end

  test "fails when key A cannot read the beneficiary", %{bypass: bypass, env: env} do
    serve(bypass, %{"/api/beneficiaries/#{@beneficiary_id}" => error(404, "not_found_error")})
    {_, output} = run(env)

    assert hd(failures(output)) =~ "key A"
    assert hd(failures(output)) =~ "MANZA_BENEFICIARY_ID"
  end
end
