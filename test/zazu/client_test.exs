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

  describe "error kinds" do
    defp error_for(status, body) do
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, status, Jason.encode!(%{"error" => body}))
      end)

      client = Zazu.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")
      {:error, %Zazu.Error{} = error} = Zazu.Entity.get(client)
      error
    end

    test "400 maps to :validation" do
      error =
        error_for(400, %{"message" => "limit is malformed", "type" => "invalid_request_error"})

      assert error.status == 400
      assert error.kind == :validation
      assert error.message == "limit is malformed"
      assert error.type == "invalid_request_error"
    end

    test "409 maps to :conflict carrying error.payment_id" do
      error =
        error_for(409, %{
          "message" => "A transfer with this client_reference already exists",
          "type" => "duplicate_client_reference",
          "param" => "client_reference",
          "payment_id" => "pay_1"
        })

      assert error.status == 409
      assert error.kind == :conflict
      assert error.type == "duplicate_client_reference"
      assert error.param == "client_reference"
      assert error.payment_id == "pay_1"
    end

    test "payment_id stays nil when a 409 omits it" do
      error = error_for(409, %{"message" => "Conflict"})

      assert error.kind == :conflict
      assert error.payment_id == nil
    end
  end

  test "the default base URL is the production host" do
    original = System.get_env("ZAZU_BASE_URL")
    System.delete_env("ZAZU_BASE_URL")
    on_exit(fn -> if original, do: System.put_env("ZAZU_BASE_URL", original) end)

    assert Zazu.new!(api_key: "test").base_url == "https://ma.manza.finance"
  end
end
