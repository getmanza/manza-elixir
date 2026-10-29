defmodule Mix.Tasks.CreateTransfer do
  @shortdoc "Creates a transfer draft (key A) and records it in the ledger"
  @moduledoc """
  The creator process (key A). Creates a transfer draft, writes it to the
  ledger from the API's response, and says where the API routed it.

      mix create_transfer          # 10.00
      mix create_transfer 250.00
  """

  use Mix.Task

  alias TransferAuthorizer.{Ledger, Routing}

  @impl true
  def run(args) do
    TransferAuthorizer.Env.overload(Path.expand(".env"))
    Mix.Task.run("app.start")

    amount = List.first(args, "10.00")
    client_reference = "example-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    creator = Manza.new!(api_key: System.fetch_env!("MANZA_CREATOR_API_KEY"))

    draft =
      case Manza.Payments.create(creator, %{
             "account_id" => System.fetch_env!("MANZA_ACCOUNT_ID"),
             "beneficiary_id" => System.fetch_env!("MANZA_BENEFICIARY_ID"),
             "amount" => amount,
             "payment_reference" => "Transfer authorizer example",
             "client_reference" => client_reference
           }) do
        {:ok, response} ->
          response.body

        # A timeout may still have created the draft: look for this
        # client_reference in the app before rerunning, or the rerun creates a
        # second transfer.
        {:error, error} ->
          Mix.raise(
            "create failed for client_reference #{client_reference}: #{Exception.message(error)} " <>
              "(type #{inspect(Map.get(error, :type))}, request_id #{inspect(Map.get(error, :request_id))})"
          )
      end

    payee = payee(draft)

    try do
      Ledger.record(Path.expand("ledger.json"), client_reference, %{
        "payment_id" => draft["id"],
        "amount" => draft["amount"],
        "currency_code" => draft["currency_code"],
        "account_id" => draft["account_id"],
        "payee" => payee
      })
    rescue
      error ->
        Mix.raise(
          "payment #{draft["id"]} (client_reference #{client_reference}) was created but not written to the ledger " <>
            "(#{Exception.message(error)}): if it reaches the authorizer, the authorizer declines it"
        )
    end

    Mix.shell().info(
      "created payment #{draft["id"]}: #{draft["amount"]} #{draft["currency_code"]} to #{payee} (client_reference #{client_reference})"
    )

    Mix.shell().info(Routing.describe(draft["authorization"]))
  end

  defp payee(%{"destination_account_id" => own}) when is_binary(own),
    do: Manza.TransferAuthorization.payee_for(destination_account_id: own)

  defp payee(%{"external_account_id" => ext}) when is_binary(ext),
    do: Manza.TransferAuthorization.payee_for(external_account_id: ext)

  defp payee(draft) do
    Mix.raise(
      "payment #{draft["id"]} names neither an external_account_id nor a destination_account_id, so it was not " <>
        "written to the ledger: if it reaches the authorizer, the authorizer declines it"
    )
  end
end
