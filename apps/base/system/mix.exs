[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.System.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_system,
      deps: deps(),
      aliases: aliases()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
      # `:os_mon` supplies `:disksup`, which is the only source of the disk rows
      # Belimbing shows. Without it both read "Unavailable", which is honest but
      # useless. It is scoped to this module's OTP app rather than the whole
      # release, and its default poll is every 30 minutes.
      extra_applications: [:logger, :os_mon]
    )
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:gettext, "~> 1.0"},
      {:phoenix_live_view, "~> 1.2.0"}
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
