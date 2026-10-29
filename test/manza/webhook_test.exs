defmodule Manza.WebhookTest do
  # Fixed test vector, shared by every SDK in the family (manza-ruby's
  # spec/manza/webhook_spec.rb). Each SDK's verifier must accept exactly this
  # delivery. The signature was computed independently with:
  #
  #   printf '%s' '1767225600.<payload>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
  use ExUnit.Case, async: true

  alias Manza.Webhook

  @secret "whsec_test_vector_secret"
  @timestamp "1767225600"
  @payload ~s({"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"})
  @signature "970fdd13680015f73dbd172884498c6fd1e07d5b5c41aae081272598607fea75"
  @now 1_767_225_600

  describe "sign/3" do
    test "signs the shared vector" do
      assert Webhook.sign(@payload, @timestamp, @secret) == @signature
    end

    test "accepts an integer timestamp" do
      assert Webhook.sign(@payload, 1_767_225_600, @secret) == @signature
    end

    test "coerces a non-binary payload, like manza-ruby" do
      assert Webhook.sign(42, @timestamp, @secret) == Webhook.sign("42", @timestamp, @secret)
    end
  end

  describe "verify?/5" do
    defp verify(overrides \\ []) do
      args =
        Keyword.merge(
          [payload: @payload, signature: @signature, timestamp: @timestamp, secret: @secret],
          overrides
        )

      opts = Keyword.take(Keyword.merge([now: @now], overrides), [:now, :tolerance])
      Webhook.verify?(args[:payload], args[:signature], args[:timestamp], args[:secret], opts)
    end

    test "accepts the shared vector" do
      assert verify() == true
    end

    test "rejects a wrong secret" do
      assert verify(secret: "whsec_other") == false
    end

    test "rejects a tampered payload" do
      assert verify(payload: String.replace(@payload, "ping", "pong")) == false
    end

    test "rejects a signature of the wrong length without raising" do
      assert verify(signature: "abc") == false
    end

    test "rejects a timestamp 301 seconds old or in the future" do
      assert verify(now: @now + 301) == false
      assert verify(now: @now - 301) == false
    end

    test "accepts a timestamp exactly at the tolerance" do
      assert verify(now: @now + 300) == true
      assert verify(now: @now - 300) == true
    end

    test "uses the current time by default" do
      assert Webhook.verify?(@payload, @signature, @timestamp, @secret) == false

      now = Integer.to_string(System.system_time(:second))
      fresh = Webhook.sign(@payload, now, @secret)
      assert Webhook.verify?(@payload, fresh, now, @secret) == true
    end

    test "skips the timestamp check with tolerance: nil" do
      assert verify(now: @now + 86_400, tolerance: nil) == true
    end

    test "raises ArgumentError on a tolerance that is neither an integer nor nil" do
      for tolerance <- ["300", :infinity, 1.5] do
        assert_raise ArgumentError, ~r/tolerance/, fn -> verify(tolerance: tolerance) end
      end
    end

    test "honours a custom tolerance" do
      assert verify(now: @now + 60, tolerance: 30) == false
      assert verify(now: @now + 60, tolerance: 60) == true
    end

    test "accepts an integer timestamp" do
      assert verify(timestamp: 1_767_225_600) == true
    end

    test "rejects a non-numeric timestamp" do
      assert verify(timestamp: "yesterday", tolerance: nil) == false
    end

    test "rejects nil inputs" do
      assert verify(signature: nil) == false
      assert verify(timestamp: nil) == false
      assert verify(payload: nil) == false
      assert verify(secret: nil) == false
    end

    test "rejects an empty secret, even with a signature made under it" do
      forged = Webhook.sign(@payload, @timestamp, "")
      assert verify(secret: "", signature: forged) == false
    end

    test "rejects a non-binary payload, even with a signature made over it" do
      forged = Webhook.sign(42, @timestamp, @secret)
      assert verify(payload: 42, signature: forged) == false
    end

    # Ruby's Integer(s, 10), which every SDK's verifier mirrors.
    test "reads a timestamp with surrounding whitespace or digit separators like manza-ruby" do
      for timestamp <- [" 1767225600 ", "\t1767225600\r\n", "1_767_225_600", "+1767225600"] do
        signature = Webhook.sign(@payload, timestamp, @secret)
        assert verify(timestamp: timestamp, signature: signature) == true, inspect(timestamp)
      end

      for timestamp <- [
            "",
            "1767225600.0",
            "1__767225600",
            "_1767225600",
            "0x10",
            "\u00a01767225600",
            "\u30001767225600"
          ] do
        signature = Webhook.sign(@payload, timestamp, @secret)

        assert verify(timestamp: timestamp, signature: signature, tolerance: nil) == false,
               inspect(timestamp)
      end
    end
  end

  describe "construct_event/4" do
    defp construct(headers, opts \\ []) do
      payload = Keyword.get(opts, :payload, @payload)
      secret = Keyword.get(opts, :secret, @secret)
      Webhook.construct_event(payload, headers, secret, Keyword.merge([now: @now], opts))
    end

    defp signed_headers(body) do
      %{
        "X-Manza-Signature" => Webhook.sign(body, @timestamp, @secret),
        "X-Manza-Timestamp" => @timestamp
      }
    end

    test "returns the parsed event for X-Manza-* headers" do
      assert construct(%{"X-Manza-Signature" => @signature, "X-Manza-Timestamp" => @timestamp}) ==
               {:ok,
                %{"event" => "test.ping", "event_id" => "0199a1b2-0000-7000-8000-000000000010"}}
    end

    test "reads mixed-case header names" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct(%{"x-MANZA-signature" => @signature, "X-manza-Timestamp" => @timestamp})
    end

    test "reads Plug's req_headers (a list of lowercase tuples)" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct([{"x-manza-signature", @signature}, {"x-manza-timestamp", @timestamp}])
    end

    test "reads Req-style list values and atom keys" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct(%{"x-manza-signature" => [@signature], x_manza_timestamp: @timestamp})
    end

    test "reads the Rack/CGI env form" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct(%{
                 "HTTP_X_MANZA_SIGNATURE" => @signature,
                 "HTTP_X_MANZA_TIMESTAMP" => @timestamp
               })
    end

    test "falls back to X-Zazu-* headers" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct(%{"X-Zazu-Signature" => @signature, "X-Zazu-Timestamp" => @timestamp})
    end

    test "prefers X-Manza-* over X-Zazu-*" do
      headers = %{
        "X-Manza-Signature" => @signature,
        "X-Manza-Timestamp" => @timestamp,
        "X-Zazu-Signature" => String.duplicate("0", 64),
        "X-Zazu-Timestamp" => "1"
      }

      assert {:ok, %{"event" => "test.ping"}} = construct(headers)
    end

    test "keeps an empty X-Manza-* header over X-Zazu-*, like manza-ruby" do
      headers = %{
        "X-Manza-Signature" => "",
        "X-Zazu-Signature" => @signature,
        "X-Manza-Timestamp" => @timestamp
      }

      assert {:error, %ArgumentError{message: "missing X-Manza-Signature header"}} =
               construct(headers)
    end

    test "fails on nil headers" do
      assert {:error, %ArgumentError{message: "missing X-Manza-Signature header"}} =
               construct(nil)
    end

    test "fails on a missing signature header" do
      assert {:error, %ArgumentError{message: "missing X-Manza-Signature header"}} =
               construct(%{"X-Manza-Timestamp" => @timestamp})
    end

    test "fails on a missing timestamp header" do
      assert {:error, %ArgumentError{message: "missing X-Manza-Timestamp header"}} =
               construct(%{"X-Manza-Signature" => @signature})
    end

    test "fails on an empty header" do
      assert {:error, %ArgumentError{message: "missing X-Manza-Signature header"}} =
               construct(%{"X-Manza-Signature" => "", "X-Manza-Timestamp" => @timestamp})
    end

    test "fails on a bad signature" do
      assert {:error, %ArgumentError{message: "invalid webhook signature"}} =
               construct(%{
                 "X-Manza-Signature" => String.duplicate("0", 64),
                 "X-Manza-Timestamp" => @timestamp
               })
    end

    test "fails on a stale timestamp" do
      assert {:error, %ArgumentError{message: "webhook timestamp outside tolerance"}} =
               construct(%{"X-Manza-Signature" => @signature, "X-Manza-Timestamp" => @timestamp},
                 now: @now + 301
               )
    end

    test "accepts a stale timestamp with tolerance: nil" do
      assert {:ok, %{"event" => "test.ping"}} =
               construct(%{"X-Manza-Signature" => @signature, "X-Manza-Timestamp" => @timestamp},
                 now: @now + 301,
                 tolerance: nil
               )
    end

    test "fails on a body that is not JSON" do
      assert {:error, %ArgumentError{message: "webhook payload is not JSON"}} =
               construct(signed_headers("not json"), payload: "not json")
    end

    test "fails on a body that is valid JSON but not an object" do
      for body <- ["[]", "null", "42"] do
        assert {:error, %ArgumentError{message: "webhook payload is not a JSON object"}} =
                 construct(signed_headers(body), payload: body)
      end
    end

    test "fails on an empty secret" do
      headers = %{
        "X-Manza-Signature" => Webhook.sign(@payload, @timestamp, ""),
        "X-Manza-Timestamp" => @timestamp
      }

      assert {:error, %ArgumentError{message: "invalid webhook signature"}} =
               construct(headers, secret: "")
    end

    test "fails, without raising, on a non-binary payload" do
      assert {:error, %ArgumentError{message: "invalid webhook signature"}} =
               construct(signed_headers(@payload), payload: 42)
    end
  end

  describe "construct_event!/4" do
    test "returns the parsed event" do
      headers = %{"X-Manza-Signature" => @signature, "X-Manza-Timestamp" => @timestamp}

      assert Webhook.construct_event!(@payload, headers, @secret, now: @now) ==
               %{"event" => "test.ping", "event_id" => "0199a1b2-0000-7000-8000-000000000010"}
    end

    test "raises ArgumentError, the signer's argument error, on a failure" do
      headers = %{
        "X-Manza-Signature" => String.duplicate("0", 64),
        "X-Manza-Timestamp" => @timestamp
      }

      assert_raise ArgumentError, "invalid webhook signature", fn ->
        Webhook.construct_event!(@payload, headers, @secret, now: @now)
      end
    end
  end
end
