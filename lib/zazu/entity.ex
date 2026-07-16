defmodule Zazu.Entity do
  @moduledoc "The current entity (the tenant the API key belongs to)."

  alias Zazu.Client

  @doc "Calls `GET /api/entity`."
  @spec get(Client.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client) do
    Client.get(client, "api/entity")
  end
end
