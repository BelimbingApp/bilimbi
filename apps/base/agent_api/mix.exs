[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.AgentApi.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_agent_api,
      deps: deps()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
  end

  # Decimal is a type an operation's result may carry, written out as a
  # string; a handler's changeset error arrives as an Ecto changeset. The
  # tests build their Authz tables through Ecto SQL.
  defp deps do
    [
      {:decimal, "~> 3.1"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"}
    ]
  end
end
