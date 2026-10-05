[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Core.User.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_core_user,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      extra_applications: [:crypto, :logger]
    )
  end

  defp deps do
    [
      {:argon2_elixir, "~> 4.1"},
      {:bcrypt_elixir, "~> 3.3"},
      {:ecto_sql, "~> 3.14"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:plug_crypto, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_pubsub, "~> 2.2"},
      {:plug, "~> 1.20"},
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
