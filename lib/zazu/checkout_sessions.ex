defmodule Zazu.CheckoutSessions do
  @moduledoc """
  One-off hosted checkout sessions. No list, update, or delete; sessions are
  created and inspected by id.
  """

  alias Zazu.Client

  @doc """
  Calls `POST /api/checkout_sessions`.

  Required attributes: `account_id`, `amount`, `success_url`.
  """
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/checkout_sessions", attributes)
  end

  @doc "Calls `GET /api/checkout_sessions/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/checkout_sessions", id]))
  end
end
