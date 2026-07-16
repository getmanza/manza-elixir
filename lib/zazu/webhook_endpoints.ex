defmodule Zazu.WebhookEndpoints do
  @moduledoc "Webhook endpoint management."

  alias Zazu.Client

  @doc """
  Calls `GET /api/webhook_endpoints`.

  ## Options

    * `:limit` — page size (1..100, default 100).
    * `:cursor` — pagination cursor.
  """
  @spec list(Client.t(), keyword()) :: {:ok, Zazu.Page.t()} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    Client.list_page(client, "api/webhook_endpoints", [], opts)
  end

  @doc "Calls `GET /api/webhook_endpoints/:id`."
  @spec get(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def get(client, id) do
    Client.get(client, Client.encode_path(["api/webhook_endpoints", id]))
  end

  @doc "Calls `POST /api/webhook_endpoints`."
  @spec create(Client.t(), map()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def create(client, attributes) do
    Client.post(client, "api/webhook_endpoints", attributes)
  end

  @doc "Calls `PATCH /api/webhook_endpoints/:id`."
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def update(client, id, attributes) do
    Client.patch(client, Client.encode_path(["api/webhook_endpoints", id]), attributes)
  end

  @doc "Calls `DELETE /api/webhook_endpoints/:id`."
  @spec delete(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def delete(client, id) do
    Client.delete(client, Client.encode_path(["api/webhook_endpoints", id]))
  end

  @doc "Calls `POST /api/webhook_endpoints/:id/test`."
  @spec test(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def test(client, id) do
    Client.post(client, Client.encode_path(["api/webhook_endpoints", id, "test"]))
  end

  @doc "Calls `POST /api/webhook_endpoints/:id/regenerate_secret`."
  @spec regenerate_secret(Client.t(), String.t()) ::
          {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def regenerate_secret(client, id) do
    Client.post(client, Client.encode_path(["api/webhook_endpoints", id, "regenerate_secret"]))
  end

  @doc "Calls `POST /api/webhook_endpoints/:id/enable`."
  @spec enable(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def enable(client, id) do
    Client.post(client, Client.encode_path(["api/webhook_endpoints", id, "enable"]))
  end

  @doc "Calls `POST /api/webhook_endpoints/:id/disable`."
  @spec disable(Client.t(), String.t()) :: {:ok, Zazu.Response.t()} | {:error, Exception.t()}
  def disable(client, id) do
    Client.post(client, Client.encode_path(["api/webhook_endpoints", id, "disable"]))
  end
end
