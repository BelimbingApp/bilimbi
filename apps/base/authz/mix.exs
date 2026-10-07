[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Authz.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_authz,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      env: [bilimbi_production_seed_provider: Bilimbi.Base.Authz.ProductionSeeds]
    )
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2.0"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
