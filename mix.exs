[discovery_file] = Path.wildcard(Path.expand("apps/base/*/mix/module_discovery.exs", __DIR__))
Code.require_file(discovery_file)
Code.require_file(Path.expand("mix/composition_lock.exs", __DIR__))

defmodule Bilimbi.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      lockfile: Bilimbi.CompositionLock.lockfile!(__DIR__),
      apps: [:base, :core, :web],
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      # CI runs `mix dialyzer` from this umbrella root, so the PLT is built here
      # and the analysis paths include every discovered module package.
      # The project's Mix tasks (`mix bilimbi.*`) call a `Mix.*` surface that needs
      # the Mix application in the PLT to type-check. PLT-only — this adds :mix to
      # Dialyzer's analysis, not to any app's runtime.
      dialyzer: [plt_add_apps: [:mix], paths: dialyzer_paths()],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "precommit.test": :test]
    ]
  end

  # One release around the Web host. Web depends on Base, Core, and every
  # mounted Domain and Extension container, so the release carries the whole
  # discovered graph without naming a module. Migrate and seed it with
  # `bin/bilimbi eval "BilimbiWeb.Release.migrate()"` and `.seed()`.
  defp releases do
    [
      bilimbi: [
        applications: [web: :permanent]
      ]
    ]
  end

  defp deps do
    [
      # Required to format HEEx from the umbrella root.
      {:phoenix_live_view, "~> 1.2.0"},
      # Project-wide, open-source development and CI checks.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      # Docs for the locked dependency versions. No `usage_rules:` key, and
      # never sync those files into a guide.
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "ecto.setup",
        "cmd --app web mix assets.setup",
        "cmd --app web mix assets.build"
      ],
      "bilimbi.server": [
        &prepare_bilimbi_server/1,
        "bilimbi.server",
        &verify_local_https/1
      ],
      "ecto.setup": ["ecto.create -r Bilimbi.Base.Repo", "bilimbi.migrate"],
      "ecto.reset": ["ecto.drop -r Bilimbi.Base.Repo", "ecto.setup"],
      precommit: [
        "compile --warnings-as-errors",
        "compile.strict",
        "deps.unlock --unused",
        "format",
        "assets.test",
        "precommit.test",
        "bilimbi.contributions.verify"
      ],
      "precommit.test": &precommit_test/1,
      "precommit.test.compatibility": &precommit_test_compatibility/1,
      "precommit.test.web": &precommit_test_web/1,
      "precommit.test.packages": &precommit_test_packages/1,
      "compile.strict": &compile_strict/1,
      "assets.test": &assets_test/1
    ]
  end

  defp prepare_bilimbi_server(_args) do
    local_https("--prepare")

    # Resolving a task from a dependency can compile that dependency closure
    # before the task runs. Load recovery from source so its graph preflight
    # also protects the first compile after a pull.
    previous = Code.get_compiler_option(:ignore_module_conflict)

    try do
      # This source definition intentionally replaces a task loaded from BEAM.
      Code.put_compiler_option(:ignore_module_conflict, true)

      Code.require_file(
        Path.expand("apps/base/module_registry/lib/mix/tasks/bilimbi.server.ex", __DIR__)
      )
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end

    Mix.shell().info("Checking and fetching locked dependencies before starting Bilimbi.")
    Mix.Task.run("deps.get")
  end

  defp verify_local_https(_args), do: local_https("--verify")

  # Shared ingress is host bootstrap, not ModuleRegistry graph recovery. Keep
  # it in the umbrella entry point; module tests and production never touch
  # a developer's Caddy service or trust stores. Source-loaded graph workspaces
  # can run this alias without configuring the Phoenix host.
  defp local_https(mode) do
    with :dev <- Mix.env(),
         endpoint when is_list(endpoint) <- Application.get_env(:web, BilimbiWeb.Endpoint) do
      host = Keyword.fetch!(Keyword.fetch!(endpoint, :url), :host)
      port = to_string(Keyword.fetch!(Keyword.fetch!(endpoint, :http), :port))

      {_output, status} =
        System.cmd("bash", [Path.join(__DIR__, "scripts/local-https.sh"), mode, host, port],
          cd: __DIR__,
          env: [
            {"BILIMBI_ELIXIR", System.find_executable("elixir")},
            {"BILIMBI_HOST_PINNED", if(System.get_env("BILIMBI_DEV_HOST"), do: "1", else: "0")},
            {"BILIMBI_PORT_PINNED", if(System.get_env("PORT"), do: "1", else: "0")}
          ],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      if status == 10, do: System.halt(0)
      if status != 0, do: Mix.raise("Local HTTPS #{mode} failed; see the diagnostic above.")

      if mode == "--prepare" do
        instance = Bilimbi.LocalConfig.load(__DIR__)["https"]
        System.put_env("BILIMBI_DEV_HOST", instance["host"])
        System.put_env("PORT", to_string(instance["port"]))
        lock_local_startup(instance["host"])
      end
    end
  end

  # The Caddy reservation protects different checkouts. Hold a kernel lock
  # through this CLI's startup as well, so two terminals in the same checkout
  # cannot race while the first VM is compiling and has no HTTP listener yet.
  defp lock_local_startup(host) do
    lock = Path.join(__DIR__, ".local/https/#{host}.startup.lock")
    flock = System.find_executable("flock") || Mix.raise("flock is required for local startup")

    port =
      Port.open({:spawn_executable, flock}, [
        :binary,
        :exit_status,
        {:line, 1024},
        {:args, ["-n", "-E", "10", lock, "bash", "-c", "printf 'locked\\n'; cat >/dev/null"]}
      ])

    receive do
      {^port, {:data, {:eol, "locked"}}} ->
        :ok

      {^port, {:exit_status, 10}} ->
        Mix.shell().info("This Bilimbi instance is already starting: https://#{host}")
        System.halt(0)

      {^port, {:exit_status, status}} ->
        Mix.raise("Could not lock local startup (exit #{status})")
    after
      5_000 ->
        Port.close(port)
        Mix.raise("Timed out locking local startup")
    end
  end

  defp precommit_test(args) do
    run_test_projects(test_projects(), args)
  end

  defp precommit_test_compatibility(args),
    do: run_test_projects(["apps/core/compatibility"], args)

  defp precommit_test_web(args), do: run_test_projects(["apps/web"], args)

  defp precommit_test_packages(args) do
    projects =
      (module_paths([:core]) -- ["apps/core/compatibility"])
      |> Kernel.++(module_paths([:base]))
      |> Kernel.++(module_paths([:domain, :extension]))

    run_test_projects(projects, args)
  end

  defp test_projects do
    module_paths([:core]) ++
      module_paths([:base]) ++ ["apps/web"] ++ module_paths([:domain, :extension])
  end

  # Each package owns its helper, OTP state, and test VM. Running packages
  # directly also ensures every package receives profiling flags.
  defp run_test_projects(projects, args) do
    mix = System.find_executable("mix") || Mix.raise("could not find mix executable")

    _ =
      Enum.reduce_while(projects, projects, fn project, remaining ->
        Mix.shell().info("==> #{project}")
        started = System.monotonic_time(:millisecond)

        {_output, status} =
          System.cmd(mix, ["test" | args],
            cd: Path.expand(project, __DIR__),
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

        elapsed = (System.monotonic_time(:millisecond) - started) / 1_000
        Mix.shell().info("Finished #{project} in #{Float.round(elapsed, 2)}s (exit #{status})")

        case status do
          0 ->
            {:cont, tl(remaining)}

          status ->
            report_skipped_precommit_tests(tl(remaining))
            exit({:shutdown, status})
        end
      end)

    :ok
  end

  defp dialyzer_paths do
    workspace_root = __DIR__
    env = Atom.to_string(Mix.env())

    host_paths =
      for app <- [:base, :core, :web] do
        Path.join([workspace_root, "_build", env, "lib", Atom.to_string(app), "ebin"])
      end

    module_paths =
      workspace_root
      |> Bilimbi.Base.ModuleRegistry.MixDiscovery.discover_workspace!()
      |> Enum.map(fn module ->
        Path.join([workspace_root, "_build", env, "lib", Atom.to_string(module.otp_app), "ebin"])
      end)

    case System.get_env("BILIMBI_DIALYZER_SCOPE") do
      "host" -> host_paths
      _all_applications -> host_paths ++ module_paths
    end
  end

  defp compile_strict(_args) do
    mix = System.find_executable("mix") || Mix.raise("could not find mix executable")

    for module <- module_paths([:base, :core, :domain, :extension]) ++ ["apps/web"] do
      Mix.shell().info("==> #{module}")

      case System.cmd(mix, ["compile", "--warnings-as-errors"],
             cd: Path.expand(module, __DIR__),
             into: IO.stream(:stdio, :line),
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {_output, status} -> exit({:shutdown, status})
      end
    end
  end

  # Mounted containers need no aliases: each module runs in its own project,
  # as the Base and Core container aliases do.
  defp module_paths(layers) do
    __DIR__
    |> Bilimbi.Base.ModuleRegistry.MixDiscovery.discover_workspace!()
    |> Enum.filter(&(&1.layer in layers))
    |> Enum.map(&Path.relative_to(&1.path, __DIR__))
  end

  # The LiveView hooks in apps/web/assets/js are tested in Node, with the test
  # runner Node ships and one DOM library (apps/web/assets/package.json). The
  # library is installed on first use and again whenever the lockfile changes.
  defp assets_test(_args) do
    dir = Path.expand("apps/web/assets", __DIR__)

    npm =
      System.find_executable("npm") ||
        Mix.raise("mix assets.test needs Node.js 22 or later, with npm, on the PATH")

    unless assets_test_installed?(dir), do: npm!(npm, ["ci", "--no-audit", "--no-fund"], dir)

    npm!(npm, ["test"], dir)
  end

  # `npm ci` writes node_modules/.package-lock.json last, so it is newer than
  # the lockfile it installed from until that lockfile changes.
  defp assets_test_installed?(dir) do
    with {:ok, %{mtime: installed}} <-
           File.stat(Path.join(dir, "node_modules/.package-lock.json")),
         {:ok, %{mtime: locked}} <- File.stat(Path.join(dir, "package-lock.json")) do
      installed >= locked
    else
      _missing -> false
    end
  end

  defp npm!(npm, args, dir) do
    case System.cmd(npm, args, cd: dir, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {_output, status} -> exit({:shutdown, status})
    end
  end

  defp report_skipped_precommit_tests([]), do: :ok

  defp report_skipped_precommit_tests(skipped) do
    Mix.shell().error("""
    Precommit stopped before running these test projects:
    #{Enum.map_join(skipped, "\n", &"  - #{&1}")}
    """)
  end
end
