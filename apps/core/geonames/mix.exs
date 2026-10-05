[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Core.Geonames.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_core_geonames,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:req, "~> 0.7"},
      {:plug, "~> 1.20"},
      {:db_connection, "~> 2.10"},
      {:decimal, "~> 3.1"},
      {:mint, "~> 1.11"},
      {:postgrex, "~> 0.22"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
