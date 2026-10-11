[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Media.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_media,
      deps: [
        {:ecto_sql, "~> 3.14"},
        {:postgrex, "~> 0.22"},
        {:phoenix, "~> 1.8.0"},
        {:plug, "~> 1.19"}
      ],
      aliases: [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
    )
  end

  def application, do: Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
end
