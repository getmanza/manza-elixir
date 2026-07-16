defmodule Zazu.ClientTest do
  # Mirror of zazu-go's client_unit_test.go.

  use ExUnit.Case

  test "new requires an API key" do
    original = System.get_env("ZAZU_API_KEY")
    System.delete_env("ZAZU_API_KEY")
    on_exit(fn -> if original, do: System.put_env("ZAZU_API_KEY", original) end)

    assert {:error, %Zazu.ConfigurationError{}} = Zazu.new()
    assert_raise Zazu.ConfigurationError, fn -> Zazu.new!() end
  end

  test "list validates the page-size cap" do
    {:ok, client} = Zazu.new(api_key: "test", base_url: "http://127.0.0.1:1")

    assert {:error, %Zazu.ConfigurationError{}} =
             Zazu.Beneficiaries.list(client, limit: Zazu.Page.max_per_page() + 1)

    assert {:error, %Zazu.ConfigurationError{}} = Zazu.Beneficiaries.list(client, limit: 0)
  end

  test "transport failures come back as connection errors" do
    {:ok, client} = Zazu.new(api_key: "test", base_url: "http://127.0.0.1:1")

    assert {:error, %Zazu.ConnectionError{}} = Zazu.Entity.get(client)
  end

  test "non-2xx responses come back as API errors" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.put_resp_header("x-request-id", "req_123")
      |> Plug.Conn.send_resp(
        404,
        ~s({"error":{"type":"not_found_error","message":"No such account","param":"id"}})
      )
    end)

    client = Zazu.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")

    assert {:error, %Zazu.Error{} = error} = Zazu.Accounts.get(client, "missing")
    assert error.status == 404
    assert error.kind == :not_found
    assert error.type == "not_found_error"
    assert error.message == "No such account"
    assert error.param == "id"
    assert error.request_id == "req_123"
  end

  test "429 carries retry_after" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "17")
      |> Plug.Conn.send_resp(429, ~s({"error":{"type":"rate_limit_error","message":"Slow down"}}))
    end)

    client = Zazu.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")

    assert {:error, %Zazu.Error{kind: :rate_limit, retry_after: 17}} = Zazu.Entity.get(client)
  end
end
