defmodule Manza.Response do
  @moduledoc """
  A successful (2xx) API response.

  `:body` is the parsed JSON body as-is — snake_case string-keyed maps, no
  struct mapping. `:raw` keeps the unparsed body; `:request_id` carries the
  `X-Request-Id` header.
  """

  defstruct [:status, :request_id, :raw, :headers, body: %{}]

  @type t :: %__MODULE__{
          status: pos_integer(),
          request_id: String.t() | nil,
          body: map() | list(),
          raw: binary(),
          headers: map()
        }
end
