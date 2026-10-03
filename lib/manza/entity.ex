defmodule Manza.Entity do
  @moduledoc "The current entity (the tenant the API key belongs to)."

  alias Manza.Client

  @doc "Calls `GET /api/entity`."
  @spec get(Client.t()) :: {:ok, Manza.Response.t()} | {:error, Exception.t()}
  def get(client) do
    Client.get(client, "api/entity")
  end
end
