[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.DateTime.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_datetime,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
  end

  defp deps do
    [
      {:postgrex, "~> 0.22"},
      {:time_zone_info, "~> 0.7"},
      {:ecto_sql, "~> 3.14"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
