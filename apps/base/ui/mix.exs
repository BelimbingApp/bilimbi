[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.UI.MixProject do
  use Mix.Project

  @workspace_root Path.expand("../../..", __DIR__)

  def project do
    [
      app: :bilimbi_base_ui,
      version: "0.1.0",
      build_path: Path.join(@workspace_root, "_build"),
      config_path: Path.join(@workspace_root, "config/config.exs"),
      deps_path: Path.join(@workspace_root, "deps"),
      lockfile: Path.join(@workspace_root, "mix.lock"),
      elixir: "~> 1.20",
      compilers: [:bilimbi_graph] ++ Mix.compilers(),
      bilimbi_module_root: __DIR__,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: Bilimbi.Base.ModuleRegistry.MixDiscovery.application_env(__DIR__)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_html, "~> 4.3"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"}
    ] ++ Bilimbi.Base.ModuleRegistry.MixDiscovery.module_dependencies(__DIR__)
  end
end
