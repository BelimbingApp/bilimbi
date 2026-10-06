[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.Grid.MixProject do
  use Mix.Project

  def project do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__,
      app: :bilimbi_base_grid,
      deps: deps()
    )
  end

  def application do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
  end

  # Ecto builds the statement a walked column reads through; Decimal is the
  # type its numeric cells arrive in.
  defp deps do
    [
      {:decimal, "~> 3.1"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"}
    ]
  end
end
