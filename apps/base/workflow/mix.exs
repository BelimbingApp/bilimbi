[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Workflow.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_workflow,
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
      {:db_connection, "~> 2.10"},
      {:phoenix_live_view, "~> 1.2.0"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
