[discovery_file] =
  Path.wildcard(Path.expand("../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.MixProject do
  use Mix.Project

  def project do
    [
      app: :base,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp deps, do: Bilimbi.Base.ModuleRegistry.MixDiscovery.container_dependencies(__DIR__)

  defp aliases do
    [
      setup: ["deps.get", "ecto.create"],
      "ecto.setup": ["ecto.create"],
      "ecto.reset": ["ecto.drop", "ecto.create"],
      test: Bilimbi.Base.ModuleRegistry.MixDiscovery.container_test_commands(__DIR__),
      "compile.strict":
        Bilimbi.Base.ModuleRegistry.MixDiscovery.container_compile_commands(__DIR__)
    ]
  end
end
