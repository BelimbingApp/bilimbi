[discovery_file] =
  Path.wildcard(Path.expand("../../../apps/base/*/mix/module_discovery.exs", __DIR__))

Code.require_file(discovery_file)

defmodule Bilimbi.Base.System.MixProject do
  use Mix.Project

  @workspace_root Path.expand("../../..", __DIR__)

  def project do
    [
      app: :bilimbi_base_system,
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
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      # `:os_mon` supplies `:disksup`, which is the only source of the disk rows
      # Belimbing shows. Without it both read "Unavailable", which is honest but
      # useless. It is scoped to this module's OTP app rather than the whole
      # release, and its default poll is every 30 minutes.
      extra_applications: [:logger, :os_mon],
      env: Bilimbi.Base.ModuleRegistry.MixDiscovery.application_env(__DIR__)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [{:ecto_sql, "~> 3.14"}] ++
      Bilimbi.Base.ModuleRegistry.MixDiscovery.module_dependencies(__DIR__)
  end

  defp aliases do
    [test: ["ecto.create --quiet -r Bilimbi.Base.Repo", "test"]]
  end
end
