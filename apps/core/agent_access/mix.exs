[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Core.AgentAccess.MixProject do
  use Mix.Project

  def project,
    do:
      Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
        app: :bilimbi_core_agent_access,
        deps: deps()
      )

  def application,
    do:
      Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__,
        extra_applications: [:crypto]
      )

  defp deps,
    do: [
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.20"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.0"}
    ]
end
