defmodule Zazu.Error do
  @moduledoc """
  The API error envelope, mirroring the other Zazu SDKs' hierarchy:
  `{"error" => {"type" => ..., "message" => ..., "param" => ...}}`.

  Match on `:kind` instead of subclassing:

    * `:authentication` — 401
    * `:forbidden` — 403
    * `:not_found` — 404
    * `:validation` — 400 (malformed request) or 422
    * `:conflict` — 409 (`:payment_id` names the existing transfer draft on a
      duplicate `client_reference`)
    * `:rate_limit` — 429 (`:retry_after` carries the `Retry-After` seconds)
    * `:server` — 5xx
    * `:api` — any other non-2xx
  """

  defexception [
    :status,
    :kind,
    :type,
    :message,
    :param,
    :request_id,
    :retry_after,
    :payment_id,
    body: %{}
  ]

  @type kind ::
          :authentication
          | :forbidden
          | :not_found
          | :validation
          | :conflict
          | :rate_limit
          | :server
          | :api

  @type t :: %__MODULE__{
          status: pos_integer(),
          kind: kind(),
          type: String.t() | nil,
          message: String.t(),
          param: String.t() | nil,
          request_id: String.t() | nil,
          retry_after: non_neg_integer() | nil,
          payment_id: String.t() | nil,
          body: map()
        }

  @impl true
  def message(%__MODULE__{param: param} = error) when is_binary(param) and param != "" do
    "zazu: #{error.message} (#{error.status} #{error.kind}, param #{param})"
  end

  def message(%__MODULE__{} = error) do
    "zazu: #{error.message} (#{error.status} #{error.kind})"
  end

  @doc false
  @spec from_response(pos_integer(), map(), term()) :: t()
  def from_response(status, headers, body) do
    payload = if is_map(body), do: Map.get(body, "error"), else: nil
    payload = if is_map(payload), do: payload, else: %{}

    %__MODULE__{
      status: status,
      kind: kind_for(status),
      type: string_or_nil(payload["type"]),
      message: string_or_nil(payload["message"]) || default_message(status),
      param: string_or_nil(payload["param"]),
      request_id: header_value(headers, "x-request-id"),
      retry_after: retry_after(status, headers),
      payment_id: string_or_nil(payload["payment_id"]),
      body: if(is_map(body), do: body, else: %{})
    }
  end

  defp kind_for(401), do: :authentication
  defp kind_for(403), do: :forbidden
  defp kind_for(404), do: :not_found
  defp kind_for(400), do: :validation
  defp kind_for(409), do: :conflict
  defp kind_for(422), do: :validation
  defp kind_for(429), do: :rate_limit
  defp kind_for(status) when status >= 500, do: :server
  defp kind_for(_status), do: :api

  defp retry_after(429, headers) do
    with value when is_binary(value) <- header_value(headers, "retry-after"),
         {seconds, _rest} <- Integer.parse(value) do
      seconds
    else
      _ -> nil
    end
  end

  defp retry_after(_status, _headers), do: nil

  defp header_value(headers, name) do
    case Map.get(headers, name) do
      [value | _rest] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil

  @reason_phrases %{
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    409 => "Conflict",
    422 => "Unprocessable Entity",
    429 => "Too Many Requests",
    500 => "Internal Server Error",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Gateway Timeout"
  }

  defp default_message(status), do: Map.get(@reason_phrases, status, "HTTP #{status}")
end

defmodule Zazu.ConfigurationError do
  @moduledoc "Returned by `Zazu.new/1` when the client can't be built."

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}

  @impl true
  def message(%__MODULE__{message: message}), do: "zazu: #{message}"
end

defmodule Zazu.ConnectionError do
  @moduledoc "Wraps transport-level failures (timeouts, DNS, refused)."

  defexception [:message, :reason]

  @type t :: %__MODULE__{message: String.t(), reason: Exception.t() | nil}

  @impl true
  def message(%__MODULE__{message: message}), do: "zazu: connection error: #{message}"
end
