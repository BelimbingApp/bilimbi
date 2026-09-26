defmodule Mix.Tasks.Compile.BilimbiGraphTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @discovery_file Path.expand("../mix/module_discovery.exs", __DIR__)
  @migration_version 20_260_814_120_000
  # compile.app compares whole-second mtimes, so every file is moved to this
  # instant before a compile. Only a change to the ebin directory's entries can
  # then make the .app stale, which is exactly what the graph marker controls.
  @settled_mtime {{2000, 1, 1}, {0, 0, 0}}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-graph-compiler-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root}
  end

  test "a graph fingerprint that returns to an earlier value rewrites the .app", %{root: root} do
    module_root = put_workspace!(root)

    put_disposition!(module_root, :compatible_baseline)
    first_fingerprint = compile_and_assert_current!(root, module_root)

    put_disposition!(module_root, :bilimbi_only)
    refute compile_and_assert_current!(root, module_root) == first_fingerprint

    put_disposition!(module_root, :compatible_baseline)
    assert compile_and_assert_current!(root, module_root) == first_fingerprint
  end

  defp compile_and_assert_current!(root, module_root) do
    settle_mtimes!(root)

    {output, status} =
      System.cmd("mix", ["compile"],
        cd: module_root,
        env: [{"MIX_ENV", "dev"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}],
        stderr_to_stdout: true
      )

    assert status == 0, output

    [bilimbi_module: expected] = MixDiscovery.application_env(module_root)
    assert compiled_descriptor(module_root) == expected

    expected.graph_fingerprint
  end

  defp compiled_descriptor(module_root) do
    app_file = Path.join(module_root, "_build/dev/lib/test_base_probe/ebin/test_base_probe.app")

    {:ok, [{:application, :test_base_probe, properties}]} =
      :file.consult(String.to_charlist(app_file))

    properties |> Keyword.fetch!(:env) |> Keyword.fetch!(:bilimbi_module)
  end

  defp settle_mtimes!(root) do
    [root | Path.wildcard(Path.join(root, "**"), match_dot: true)]
    |> Enum.each(&File.touch!(&1, @settled_mtime))
  end

  defp put_workspace!(root) do
    File.mkdir_p!(Path.join(root, "apps/base"))
    File.write!(Path.join(root, "mix.exs"), "[]\n")

    File.write!(
      Path.join(root, "apps/base/bilimbi.container.exs"),
      inspect(id: "base", kind: :container, layer: :base) <> "\n"
    )

    module_root = Path.join(root, "apps/base/probe")

    for directory <- ["test", "docs", "priv/repo/migrations"] do
      File.mkdir_p!(Path.join(module_root, directory))
    end

    File.write!(
      Path.join(module_root, "priv/repo/migrations/#{@migration_version}_probe.exs"),
      "defmodule Test.Base.Probe.Migration do\nend\n"
    )

    File.write!(Path.join(module_root, "mix.exs"), """
    Code.require_file(#{inspect(@discovery_file)})

    defmodule Test.Base.Probe.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_base_probe,
          version: "0.1.0",
          compilers: [:bilimbi_graph] ++ Mix.compilers(),
          bilimbi_module_root: __DIR__,
          deps: []
        ]
      end

      def application do
        [env: Bilimbi.Base.ModuleRegistry.MixDiscovery.application_env(__DIR__)]
      end
    end
    """)

    module_root
  end

  defp put_disposition!(module_root, disposition) do
    descriptor = [
      id: "base/probe",
      kind: :module,
      layer: :base,
      required: true,
      otp_app: :test_base_probe,
      namespace: Test.Base.Probe,
      dependencies: [],
      migrations: "priv/repo/migrations",
      migration_dispositions: %{@migration_version => disposition},
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(
      Path.join(module_root, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )
  end
end
