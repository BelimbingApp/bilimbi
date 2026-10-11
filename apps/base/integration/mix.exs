[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Integration.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_integration,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      extra_applications: [:logger, :crypto]
    )
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8.9"},
      {:ecto_sql, "~> 3.14"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:req, "~> 0.7"},
      {:plug, "~> 1.20"},
      {:mint, "~> 1.11"}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet -r Bilimbi.Base.Repo",
        "ecto.migrate --quiet -r Bilimbi.Base.Repo --migrations-path ../queue/priv/repo/migrations",
        "test"
      ]
    ]
  end
end
