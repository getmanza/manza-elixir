defmodule Manza.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/getmanza/manza-elixir"

  def project do
    [
      app: :manza,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "manza",
      description: "Elixir SDK for the Manza API",
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:yaml_elixir, "~> 2.11", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp package do
    [
      name: "manza",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
