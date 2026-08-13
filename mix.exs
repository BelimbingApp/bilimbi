defmodule Bilimbi.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      # Required to format HEEx from the umbrella root.
      {:phoenix_live_view, "~> 1.2.0"},
      # Project-wide, open-source development and CI checks.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup", "bilimbi.migrate"],
      "ecto.setup": ["ecto.create -r Bilimbi.Base.Repo", "bilimbi.migrate"],
      "ecto.reset": ["ecto.drop -r Bilimbi.Base.Repo", "ecto.setup"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test",
        "bilimbi.contributions.verify"
      ]
    ]
  end
end
