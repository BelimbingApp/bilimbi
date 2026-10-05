[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Core.Employee.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_core_employee,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      env: [bilimbi_production_seed_provider: Bilimbi.Core.Employee.ProductionSeeds]
    )
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_html, "~> 4.3"},
      {:postgrex, "~> 0.22"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
