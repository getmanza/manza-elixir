defmodule Manza.Webhook do
  @moduledoc """
  Verifies incoming webhook deliveries. Pure functions, no HTTP.

  Every delivery carries `X-Manza-Signature` (lowercase hex HMAC-SHA256 of
  `"<timestamp>.<raw body>"` under the endpoint's signing secret) and
  `X-Manza-Timestamp` (Unix seconds, fresh on every attempt). The legacy
  `X-Zazu-*` names carry the same values.

  Pass the **raw request body**, never re-encoded JSON. In a Plug, read it
  before any `Plug.Parsers` consumes it:

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case Manza.Webhook.construct_event(body, conn.req_headers, signing_secret) do
        {:ok, event} -> event["event"] # => "payment.authorization_requested"
        {:error, %ArgumentError{message: message}} -> Plug.Conn.send_resp(conn, 401, message)
      end

  Failures use `ArgumentError`, the same argument error
  `Manza.TransferAuthorization` raises: no new error type.

  ## Options

    * `:tolerance` — seconds the timestamp may be off from `:now` (default
      `300`). `nil` skips the timestamp check: only to replay a captured
      delivery in a local tool or test, never on a live endpoint.
    * `:now` — the current time in Unix seconds (default: the system clock).
  """

  @default_tolerance 300

  @doc """
  Lowercase hex HMAC-SHA256 of `"<timestamp>.<payload>"`. For tests and local
  tools. `payload` and `timestamp` are interpolated as they are, like
  manza-ruby's `sign`.
  """
  @spec sign(String.Chars.t(), String.t() | integer(), String.t()) :: String.t()
  def sign(payload, timestamp, secret) when is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, "#{timestamp}.#{payload}")
    |> Base.encode16(case: :lower)
  end

  @doc """
  `true` when the signature matches (constant time) and the timestamp is
  within the tolerance of now. Never raises on bad input; returns `false`.
  """
  @spec verify?(term(), term(), term(), term(), keyword()) :: boolean()
  def verify?(payload, signature, timestamp, secret, opts \\ []) do
    signature_matches?(payload, signature, timestamp, secret) and
      timestamp_fresh?(timestamp, opts)
  end

  @doc """
  Reads `X-Manza-Signature` and `X-Manza-Timestamp` from `headers`, verifies
  them, and returns `{:ok, event}` with the parsed JSON object.

  `headers` is a map or a list of `{name, value}` pairs (Plug's
  `conn.req_headers`, Req's response headers). Names are read in any case,
  in the CGI `HTTP_X_MANZA_*` form too, falling back to `X-Zazu-*`; a list
  value reads its first element.

  Returns `{:error, %ArgumentError{}}` when a header is missing, the signature
  does not match, the timestamp is outside the tolerance, or the body is not a
  JSON object.
  """
  @spec construct_event(String.t(), map() | [{term(), term()}], String.t(), keyword()) ::
          {:ok, map()} | {:error, ArgumentError.t()}
  def construct_event(payload, headers, secret, opts \\ []) do
    normalized = normalize_headers(headers)

    with {:ok, signature} <- header(normalized, "signature"),
         {:ok, timestamp} <- header(normalized, "timestamp"),
         :ok <-
           check(
             signature_matches?(payload, signature, timestamp, secret),
             "invalid webhook signature"
           ),
         :ok <- check(timestamp_fresh?(timestamp, opts), "webhook timestamp outside tolerance") do
      decode(payload)
    end
  end

  @doc "Same as `construct_event/4`, but returns the event or raises `ArgumentError`."
  @spec construct_event!(String.t(), map() | [{term(), term()}], String.t(), keyword()) :: map()
  def construct_event!(payload, headers, secret, opts \\ []) do
    case construct_event(payload, headers, secret, opts) do
      {:ok, event} -> event
      {:error, error} -> raise error
    end
  end

  defp signature_matches?(payload, signature, timestamp, secret)
       when is_binary(payload) and is_binary(signature) and is_binary(secret) and secret != "" do
    case parse_timestamp(timestamp) do
      nil -> false
      _seconds -> secure_compare(sign(payload, timestamp, secret), signature)
    end
  end

  defp signature_matches?(_payload, _signature, _timestamp, _secret), do: false

  defp timestamp_fresh?(timestamp, opts) do
    case Keyword.get(opts, :tolerance, @default_tolerance) do
      nil ->
        true

      tolerance ->
        now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)
        seconds = parse_timestamp(timestamp)
        seconds != nil and abs(now - seconds) <= tolerance
    end
  end

  defp parse_timestamp(timestamp) when is_integer(timestamp), do: timestamp

  # What Ruby's Integer(timestamp, 10) accepts: surrounding whitespace, a sign,
  # and single underscores between digits.
  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    trimmed = String.trim(timestamp)

    if Regex.match?(~r/\A[+-]?\d+(?:_\d+)*\z/, trimmed) do
      trimmed |> String.replace("_", "") |> String.to_integer()
    end
  end

  defp parse_timestamp(_timestamp), do: nil

  # Constant time for equal lengths; the length of an HMAC is no secret.
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp normalize_headers(headers) do
    Enum.reduce(headers, %{}, fn {name, value}, acc ->
      key =
        name
        |> to_string()
        |> String.replace(~r/\AHTTP_/i, "")
        |> String.replace("_", "-")
        |> String.downcase()

      Map.put_new(acc, key, first_value(value))
    end)
  end

  defp first_value([value | _rest]), do: value
  defp first_value(value), do: value

  defp header(normalized, suffix) do
    value =
      present(normalized["x-manza-" <> suffix]) || present(normalized["x-zazu-" <> suffix])

    if value,
      do: {:ok, value},
      else:
        {:error, %ArgumentError{message: "missing X-Manza-#{String.capitalize(suffix)} header"}}
  end

  defp present(value) when is_integer(value), do: Integer.to_string(value)
  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  defp check(true, _message), do: :ok
  defp check(false, message), do: {:error, %ArgumentError{message: message}}

  defp decode(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = event} -> {:ok, event}
      {:ok, _other} -> {:error, %ArgumentError{message: "webhook payload is not a JSON object"}}
      {:error, _reason} -> {:error, %ArgumentError{message: "webhook payload is not JSON"}}
    end
  end
end
