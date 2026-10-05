[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Perf.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_perf,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      mod: {Bilimbi.Base.Perf.Application, []}
    )
  end

  defp deps do
    [
      {:db_connection, "~> 2.10"},
      {:decimal, "~> 3.1"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},
      {:oban, "~> 2.23"},
      {:phoenix_live_view, "~> 1.2.0"}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet -r Bilimbi.Base.Repo",
        "ecto.migrate --quiet -r Bilimbi.Base.Repo --migrations-path priv/repo/migrations",
        "test"
      ]
    ]
  end
end
