[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Queue.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_queue,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      mod: {Bilimbi.Base.Queue.Application, []}
    )
  end

  defp deps do
    [
      {:oban, "~> 2.23"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:plug_crypto, "~> 2.2"}
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
