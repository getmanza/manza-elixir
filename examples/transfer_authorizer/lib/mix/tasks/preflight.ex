defmodule Mix.Tasks.Preflight do
  @shortdoc "Checks every setup step and prints the fix for each that fails"
  @moduledoc """
  Runs `TransferAuthorizer.Preflight` with `.env` loaded. Exits with status 1
  when a step fails.

      mix preflight          # for a 10.00 transfer
      mix preflight 250.00
  """

  use Mix.Task

  @impl true
  def run(args) do
    TransferAuthorizer.Env.overload(Path.expand(".env"))
    Mix.Task.run("app.start")

    unless TransferAuthorizer.Preflight.run(amount: List.first(args, "10.00")) do
      exit({:shutdown, 1})
    end
  end
end
