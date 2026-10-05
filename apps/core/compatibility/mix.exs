[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Core.Compatibility.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_core_compatibility,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      mod: if(Mix.env() == :test, do: {Bilimbi.Core.Compatibility.RuntimeSchemaFixture, []}),
      extra_applications: [:logger, :crypto]
    )
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:db_connection, "~> 2.10"},
      {:oban, "~> 2.23"},
      {:postgrex, "~> 0.22"}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet -r Bilimbi.Base.Repo",
        "run --no-start -e Bilimbi.Base.Queue.TestFixtures.ensure_runtime_tables!()",
        "test"
      ]
    ]
  end
end
