defmodule Manza.ClientTest do
  # Mirror of manza-go's client_unit_test.go.

  use ExUnit.Case

  import ExUnit.CaptureLog

  @env_vars ~w(MANZA_API_KEY MANZA_BASE_URL MANZA_API_VERSION ZAZU_API_KEY ZAZU_BASE_URL ZAZU_API_VERSION)

  setup do
    originals = Map.new(@env_vars, &{&1, System.get_env(&1)})

    Enum.each(@env_vars, fn name ->
      System.delete_env(name)
      :persistent_term.erase({Manza.Client, :deprecated_env, name})
    end)

    on_exit(fn ->
      Enum.each(originals, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  test "new requires an API key" do
    assert {:error, %Manza.ConfigurationError{}} = Manza.new()
    assert_raise Manza.ConfigurationError, fn -> Manza.new!() end
  end

  describe "env vars" do
    test "MANZA_* vars are read without a warning" do
      System.put_env("MANZA_API_KEY", "manza-key")
      System.put_env("MANZA_BASE_URL", "https://example.test/")
      System.put_env("MANZA_API_VERSION", "2026-10-01")

      log = capture_log(fn -> assert {:ok, _client} = Manza.new() end)

      assert log == ""
      client = Manza.new!()
      assert client.api_key == "manza-key"
      assert client.base_url == "https://example.test"
      assert client.api_version == "2026-10-01"
    end

    test "ZAZU_* vars are the fallback and warn" do
      System.put_env("ZAZU_API_KEY", "zazu-key")
      System.put_env("ZAZU_BASE_URL", "https://legacy.test")
      System.put_env("ZAZU_API_VERSION", "2026-01-01")

      log =
        capture_log(fn ->
          client = Manza.new!()
          assert client.api_key == "zazu-key"
          assert client.base_url == "https://legacy.test"
          assert client.api_version == "2026-01-01"
        end)

      for name <- ~w(API_KEY BASE_URL API_VERSION) do
        assert log =~ "ZAZU_#{name} is deprecated, use MANZA_#{name}"
      end
    end

    test "MANZA_* wins over ZAZU_* and does not warn" do
      System.put_env("MANZA_API_KEY", "manza-key")
      System.put_env("ZAZU_API_KEY", "zazu-key")

      log = capture_log(fn -> assert Manza.new!().api_key == "manza-key" end)

      assert log == ""
    end

    test "the deprecation warning is logged once per variable" do
      System.put_env("ZAZU_API_KEY", "zazu-key")

      first = capture_log(fn -> Manza.new!() end)
      second = capture_log(fn -> Manza.new!() end)

      assert first =~ "ZAZU_API_KEY is deprecated"
      assert second == ""
    end

    test "explicit options skip the env lookup entirely" do
      System.put_env("ZAZU_API_KEY", "zazu-key")

      log = capture_log(fn -> assert Manza.new!(api_key: "opt-key").api_key == "opt-key" end)

      assert log == ""
    end
  end

  test "requests carry the manza-version header and a manza-elixir user agent" do
    bypass = Bypass.open()
    test_pid = self()

    Bypass.expect(bypass, fn conn ->
      send(test_pid, {:headers, Map.new(conn.req_headers)})
      Plug.Conn.send_resp(conn, 200, "{}")
    end)

    client =
      Manza.new!(
        api_key: "test",
        api_version: "2026-10-01",
        base_url: "http://localhost:#{bypass.port}"
      )

    assert {:ok, _} = Manza.Entity.get(client)
    assert_receive {:headers, headers}
    assert headers["manza-version"] == "2026-10-01"
    assert headers["user-agent"] == "manza-elixir/" <> Manza.version()
    refute Map.has_key?(headers, "zazu-version")
  end

  test "list validates the page-size cap" do
    {:ok, client} = Manza.new(api_key: "test", base_url: "http://127.0.0.1:1")

    assert {:error, %Manza.ConfigurationError{}} =
             Manza.Beneficiaries.list(client, limit: Manza.Page.max_per_page() + 1)

    assert {:error, %Manza.ConfigurationError{}} = Manza.Beneficiaries.list(client, limit: 0)
  end

  test "transport failures come back as connection errors" do
    {:ok, client} = Manza.new(api_key: "test", base_url: "http://127.0.0.1:1")

    assert {:error, %Manza.ConnectionError{}} = Manza.Entity.get(client)
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

    client = Manza.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")

    assert {:error, %Manza.Error{} = error} = Manza.Accounts.get(client, "missing")
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

    client = Manza.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")

    assert {:error, %Manza.Error{kind: :rate_limit, retry_after: 17}} = Manza.Entity.get(client)
  end

  describe "error kinds" do
    defp error_for(status, body) do
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, status, Jason.encode!(%{"error" => body}))
      end)

      client = Manza.new!(api_key: "test", base_url: "http://localhost:#{bypass.port}")
      {:error, %Manza.Error{} = error} = Manza.Entity.get(client)
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
    assert Manza.new!(api_key: "test").base_url == "https://ma.manza.finance"
  end
end
