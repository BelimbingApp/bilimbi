Code.require_file(Path.expand("mix/module_discovery.exs", __DIR__))

defmodule Bilimbi.Base.ModuleRegistry.MixProject do
  use Mix.Project

  @workspace_root Path.expand("../../..", __DIR__)

  def project do
    [
      app: :bilimbi_base_module_registry,
      version: "0.1.0",
      build_path: Path.join(@workspace_root, "_build"),
      config_path: Path.join(@workspace_root, "config/config.exs"),
      deps_path: Path.join(@workspace_root, "deps"),
      lockfile: Path.join(@workspace_root, "mix.lock"),
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: Bilimbi.Base.ModuleRegistry.MixDiscovery.module_dependencies(__DIR__)
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: Bilimbi.Base.ModuleRegistry.MixDiscovery.application_env(__DIR__)
    ]
  end
end
