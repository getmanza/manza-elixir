defmodule Zazu.Page do
  @moduledoc """
  One page of a cursor-paginated list endpoint:
  `{"data" => [...], "has_more" => bool, "next_cursor" => string | nil}`.

  The API caps page size at 100 records; `:limit` is validated against that
  cap before the request is made.
  """

  defstruct data: [], has_more: false, next_cursor: nil, response: nil, fetch: nil

  @type t :: %__MODULE__{
          data: [map()],
          has_more: boolean(),
          next_cursor: String.t() | nil,
          response: Zazu.Response.t(),
          fetch: (String.t() -> {:ok, t()} | {:error, Exception.t()})
        }

  @max_per_page 100

  @doc "The API's hard page-size cap."
  @spec max_per_page() :: pos_integer()
  def max_per_page, do: @max_per_page

  @doc """
  Fetches the following page as `{:ok, page}`, or returns `nil` when this is
  the last one.
  """
  @spec next(t()) :: {:ok, t()} | {:error, Exception.t()} | nil
  def next(%__MODULE__{has_more: false}), do: nil
  def next(%__MODULE__{next_cursor: cursor}) when cursor in [nil, ""], do: nil
  def next(%__MODULE__{fetch: fetch, next_cursor: cursor}), do: fetch.(cursor)

  @doc false
  @spec from_response(Zazu.Response.t(), (String.t() -> {:ok, t()} | {:error, Exception.t()})) ::
          t()
  def from_response(%Zazu.Response{} = response, fetch) do
    body = if is_map(response.body), do: response.body, else: %{}

    %__MODULE__{
      data: rows(body["data"]),
      has_more: body["has_more"] == true,
      next_cursor: if(is_binary(body["next_cursor"]), do: body["next_cursor"]),
      response: response,
      fetch: fetch
    }
  end

  defp rows(data) when is_list(data), do: Enum.filter(data, &is_map/1)
  defp rows(_data), do: []
end
