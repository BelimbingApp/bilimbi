[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Settings.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_settings,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      mod: {Bilimbi.Base.Settings.Application, []},
      extra_applications: [:crypto, :logger]
    )
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:postgrex, "~> 0.22"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
