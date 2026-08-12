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
      {:phoenix_live_view, "~> 1.2.0"}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup", "bilimbi.migrate"],
      "ecto.setup": ["ecto.create -r Bilimbi.Base.Repo", "bilimbi.migrate"],
      "ecto.reset": ["ecto.drop -r Bilimbi.Base.Repo", "ecto.setup"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
