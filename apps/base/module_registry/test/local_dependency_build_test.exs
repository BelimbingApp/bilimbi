defmodule Bilimbi.Base.ModuleRegistry.LocalDependencyBuildTest do
  use ExUnit.Case,
    async: true,
    parameterize: [%{environment: "test"}, %{environment: "prod"}]

  @discovery_file Path.expand("../mix/module_discovery.exs", __DIR__)

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-local-build-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    put_workspace!(root)
    %{root: root}
  end

  test "host and package builds agree on support across a mounted dependency closure", %{
    root: root,
    environment: environment
  } do
    compile!(root, environment)
    assert_support(root, environment)

    # These are generated compiler outputs. Their presence proves that a
    # dependency build retained test support; their mtimes prove that moving
    # between host and owner did not rebuild unchanged packages.
    beams = Path.wildcard(Path.join(root, "_build/#{environment}/lib/*/ebin/*.beam"))
    assert beams != []
    Enum.each(beams, &File.touch!(&1, {{2000, 1, 1}, {0, 0, 0}}))
    mtimes = Map.new(beams, &{&1, File.stat!(&1).mtime})

    compile!(Path.join(root, "apps/domains/probe/consumer"), environment)
    compile!(root, environment)

    assert_support(root, environment)
    assert Map.new(beams, &{&1, File.stat!(&1).mtime}) == mtimes

    # The mounted container contributes no routes. Removing it must still
    # refresh the host's OTP dependencies, without relying on an incidental
    # source recompile to discard the old .app's application list.
    File.rm_rf!(Path.join(root, "apps/domains/probe"))

    for app <- [:probe, :fixture_probe_consumer] do
      File.rm_rf!(Path.join(root, "_build/#{environment}/lib/#{app}"))
    end

    run_mix!(root, environment, [
      "do",
      "compile",
      "--warnings-as-errors",
      "+",
      "run",
      "--no-compile",
      "-e",
      "IO.puts(:host_started)"
    ])
  end

  defp assert_support(root, environment) do
    for {app, module} <- [
          {:fixture_base_library, Fixture.LibrarySupport},
          {:fixture_probe_consumer, Fixture.ConsumerSupport}
        ] do
      beam = Path.join(root, "_build/#{environment}/lib/#{app}/ebin/#{module}.beam")
      assert File.regular?(beam) == (environment == "test"), beam
    end
  end

  defp compile!(path, environment) do
    run_mix!(path, environment, ["compile", "--warnings-as-errors"])
  end

  defp run_mix!(path, environment, arguments) do
    {output, status} =
      System.cmd("mix", arguments,
        cd: path,
        env: [
          {"MIX_ENV", environment},
          {"MIX_BUILD_PATH", nil},
          {"MIX_DEPS_PATH", nil},
          {"BILIMBI_COMPOSITION_PINNED", nil}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp put_workspace!(root) do
    base = Path.join(root, "apps/base")
    domain = Path.join(root, "apps/domains/probe")

    for {path, id, layer} <- [{base, "base", :base}, {domain, "probe", :domain}] do
      File.mkdir_p!(path)

      File.write!(
        Path.join(path, "bilimbi.container.exs"),
        inspect(id: id, kind: :container, layer: layer)
      )
    end

    put_project!(
      root,
      :fixture_host,
      """
      [{:base, path: "apps/base", env: Mix.env()}] ++
        Bilimbi.Base.ModuleRegistry.MixDiscovery.optional_container_dependencies(__DIR__)
      """,
      "compilers: [:bilimbi_graph] ++ Mix.compilers(), bilimbi_workspace_root: __DIR__,"
    )

    put_project!(
      base,
      :base,
      "Bilimbi.Base.ModuleRegistry.MixDiscovery.container_dependencies(__DIR__)"
    )

    put_project!(
      domain,
      :probe,
      "Bilimbi.Base.ModuleRegistry.MixDiscovery.container_dependencies(__DIR__)"
    )

    put_module!(root, base, "library", :base, :fixture_base_library, Fixture.Library, [])

    put_module!(root, domain, "consumer", :domain, :fixture_probe_consumer, Fixture.Consumer, [
      "base/library"
    ])
  end

  defp put_project!(path, app, dependencies, options \\ "") do
    File.write!(Path.join(path, "mix.exs"), """
    Code.require_file(#{inspect(@discovery_file)})

    defmodule Fixture.#{Macro.camelize(Atom.to_string(app))}.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0", #{options} deps: (#{dependencies})]
      end
    end
    """)
  end

  defp put_module!(root, container, name, layer, app, namespace, dependencies) do
    path = Path.join(container, name)
    for dir <- ["lib", "test/support", "docs"], do: File.mkdir_p!(Path.join(path, dir))

    descriptor = [
      id: "#{Path.basename(container)}/#{name}",
      kind: :module,
      layer: layer,
      required: true,
      otp_app: app,
      namespace: namespace,
      dependencies: dependencies,
      migrations: nil,
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(Path.join(path, "bilimbi.module.exs"), inspect(descriptor))

    put_project!(
      path,
      app,
      "Bilimbi.Base.ModuleRegistry.MixDiscovery.module_dependencies(__DIR__)",
      """
      build_path: #{inspect(Path.join(root, "_build"))},
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      """
    )

    File.write!(Path.join(path, "lib/#{name}.ex"), "defmodule #{namespace} do\nend\n")

    File.write!(
      Path.join(path, "test/support/support.ex"),
      "defmodule #{namespace}Support do\nend\n"
    )
  end
end
