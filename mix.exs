defmodule Zazu.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/getzazu/zazu-elixir"

  def project do
    [
      app: :zazu,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "zazu",
      description: "Elixir SDK for the Zazu API",
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp package do
    [
      name: "zazu",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
