Code.require_file(Path.expand("../base/module_registry/mix/module_discovery.exs", __DIR__))

defmodule Bilimbi.Web.MixProject do
  use Mix.Project

  def project do
    [
      app: :web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: test_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:bilimbi_graph, :phoenix_live_view] ++ Mix.compilers(),
      bilimbi_workspace_root: Path.expand("../..", __DIR__),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {BilimbiWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp test_paths(:test) do
    ["test" | Bilimbi.Base.ModuleRegistry.MixDiscovery.web_test_paths(Path.expand("../..", __DIR__))]
  end

  defp test_paths(_env), do: ["test"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2"},
      {:bandit, "~> 1.12"},
      {:swoosh, "~> 1.27"},
      {:gen_smtp, "~> 1.3"},
      {:req, "~> 0.7"},
      {:base, in_umbrella: true},
      {:core, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: [
        "ecto.create --quiet -r Bilimbi.Base.Repo",
        "ecto.migrate --quiet -r Bilimbi.Base.Repo --migrations-path ../base/queue/priv/repo/migrations",
        "test"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind bilimbi_web", "esbuild bilimbi_web"],
      "assets.deploy": [
        "tailwind bilimbi_web --minify",
        "esbuild bilimbi_web --minify",
        "phx.digest"
      ]
    ]
  end
end
