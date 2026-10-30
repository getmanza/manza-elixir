defmodule TransferAuthorizer.MixProject do
  use Mix.Project

  def project do
    [
      app: :transfer_authorizer,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # The SDK from this checkout. plug, bandit and decimal are this example's
  # own dependencies: the manza package gains none.
  defp deps do
    [
      {:manza, path: "../.."},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:decimal, "~> 3.2"},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
