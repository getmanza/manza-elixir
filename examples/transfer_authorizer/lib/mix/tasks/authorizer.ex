defmodule Mix.Tasks.Authorizer do
  @shortdoc "Runs the transfer authorizer (key B) on PORT (default 4599)"
  @moduledoc """
  The authorizer process (key B). Reads `.env`, then serves
  `TransferAuthorizer.App` with Bandit until stopped:

      mix authorizer
  """

  use Mix.Task

  @impl true
  def run(_args) do
    TransferAuthorizer.Env.overload(Path.expand(".env"))

    missing =
      Enum.filter(
        ~w(MANZA_AUTHORIZER_API_KEY MANZA_AUTHORIZER_SECRET),
        &(System.get_env(&1, "") == "")
      )

    if missing != [],
      do: Mix.raise("Set #{Enum.join(missing, " and ")} in #{Path.expand(".env")}")

    Mix.Task.run("app.start")

    port = String.to_integer(System.get_env("PORT", "4599"))

    opts = [
      client: Manza.new!(api_key: System.fetch_env!("MANZA_AUTHORIZER_API_KEY")),
      secret: System.fetch_env!("MANZA_AUTHORIZER_SECRET"),
      ledger: Path.expand("ledger.json"),
      allow_new_payees: allow_new_payees?()
    ]

    {:ok, _pid} = Bandit.start_link(plug: {TransferAuthorizer.App, opts}, port: port)
    Mix.shell().info("authorizer listening on port #{port}")
    Process.sleep(:infinity)
  end

  defp allow_new_payees? do
    value = System.get_env("ALLOW_NEW_PAYEES", "true") |> String.trim() |> String.downcase()
    value not in ~w(false 0 no)
  end
end
