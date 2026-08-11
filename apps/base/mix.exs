defmodule Bilimbi.Base.MixProject do
  use Mix.Project

  def project do
    [
      app: :base,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Bilimbi.Base.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:jason, "~> 1.4"},
      {:swoosh, "~> 1.27"},
      {:req, "~> 0.7"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create"],
      "ecto.setup": ["ecto.create"],
      "ecto.reset": ["ecto.drop", "ecto.create"],
      test: ["ecto.create --quiet", "test"]
    ]
  end
end
