defmodule Mix.Tasks.Bilimbi.ServerRecoveryTest do
  use ExUnit.Case, async: true

  @discovery_file Path.expand("../mix/module_discovery.exs", __DIR__)
  @server_file Path.expand("../lib/mix/tasks/bilimbi.server.ex", __DIR__)
  @root_mix_file Path.expand("../../../../mix.exs", __DIR__)
  @lock_file Path.expand("../../../../mix/composition_lock.exs", __DIR__)

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-server-recovery-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    put_workspace!(root)

    put_module!(root, "consumer", [])

    put_source!(
      root,
      "consumer",
      "defmodule Test.Core.Consumer do\n def page, do: :original\nend"
    )

    {output, status} = mix(root, ["compile"])
    assert status == 0, output
    %{root: root}
  end

  test "repairs a newly added dependency before compiling its consumer", %{root: root} do
    put_module!(root, "page", [])
    put_source!(root, "page", "defmodule Test.Base.Page do\n defstruct [:value]\nend")
    put_module!(root, "consumer", ["base/page"])

    put_source!(
      root,
      "consumer",
      "defmodule Test.Core.Consumer do\n def page, do: %Test.Base.Page{value: :ready}\nend"
    )

    refute File.exists?(Path.join(root, "_build/dev/lib/test_base_page/ebin/test_base_page.app"))
    {output, status} = mix(root, ["bilimbi.server", "--no-migrate"])
    assert status == 0, output
    assert output =~ "Workspace graph metadata is stale; rebuilding dependencies."
    assert File.read!(Path.join(root, "server-started")) == "%Test.Base.Page{value: :ready}"

    {output, status} = mix(root, ["bilimbi.server", "--no-migrate"])
    assert status == 0, output
    refute output =~ "rebuilding dependencies"
  end

  test "leaves unrelated compilation failures visible without starting Phoenix", %{root: root} do
    put_source!(
      root,
      "consumer",
      "defmodule Test.Core.Consumer do\n def page, do: missing_function()\nend"
    )

    {output, status} = mix(root, ["bilimbi.server", "--no-migrate"])
    assert status != 0
    assert output =~ "undefined function missing_function/0"
    refute output =~ "rebuilding dependencies"
    refute File.exists?(Path.join(root, "server-started"))
  end

  test "an unrelated compile error still stops a stale-graph rebuild", %{root: root} do
    put_module!(root, "page", [])
    put_source!(root, "page", "defmodule Test.Base.Page do\n defstruct [:value]\nend")
    put_module!(root, "consumer", ["base/page"])

    put_source!(
      root,
      "consumer",
      "defmodule Test.Core.Consumer do\n def page, do: missing_function()\nend"
    )

    {output, status} = mix(root, ["bilimbi.server", "--no-migrate"])
    assert status != 0
    assert output =~ "undefined function missing_function/0"
    assert length(Regex.scan(~r/Workspace graph metadata is stale;/, output)) == 1
    refute output =~ "workspace graph metadata remains stale"
    refute File.exists?(Path.join(root, "server-started"))
  end

  defp mix(root, args) do
    System.cmd("mix", args,
      cd: root,
      env: [{"MIX_ENV", "dev"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}],
      stderr_to_stdout: true
    )
  end

  defp put_workspace!(root) do
    File.mkdir_p!(Path.join(root, "apps/base"))
    File.mkdir_p!(Path.join(root, "apps/core"))
    File.mkdir_p!(Path.join(root, "mix"))
    File.mkdir_p!(Path.join(root, "config"))
    File.cp!(@lock_file, Path.join(root, "mix/composition_lock.exs"))
    File.write!(Path.join(root, "config/config.exs"), "import Config\n")

    put_module!(root, "module_registry", [])
    registry = Path.join(root, "apps/base/module_registry")
    File.mkdir_p!(Path.join(registry, "mix"))
    File.mkdir_p!(Path.join(registry, "lib/mix/tasks"))
    File.cp!(@server_file, Path.join(registry, "lib/mix/tasks/bilimbi.server.ex"))

    for source <- Path.wildcard(Path.join(Path.dirname(@discovery_file), "*.exs")) do
      File.cp!(source, Path.join(registry, "mix/#{Path.basename(source)}"))
    end

    # Run the real root alias as well as the task: Mix's task lookup can
    # otherwise compile dependencies before run/1 ever gets control.
    File.cp!(@root_mix_file, Path.join(root, "workspace_project.exs"))

    File.write!(Path.join(root, "mix.exs"), """
    Code.require_file("workspace_project.exs", __DIR__)
    Mix.Project.pop()
    defmodule Test.Workspace.MixProject do
      use Mix.Project
      def project do
        Bilimbi.Umbrella.MixProject.project()
        |> Keyword.merge(apps: [:base, :core], deps: [], listeners: [])
      end
    end
    defmodule Mix.Tasks.Phx.Server do
      use Mix.Task
      def run(_args), do: File.write!("server-started", inspect(Test.Core.Consumer.page()))
    end
    """)

    for layer <- [:base, :core] do
      File.write!(
        Path.join(root, "apps/#{layer}/bilimbi.container.exs"),
        inspect(id: to_string(layer), kind: :container, layer: layer)
      )

      File.write!(Path.join(root, "apps/#{layer}/mix.exs"), """
      defmodule Test.#{Macro.camelize(to_string(layer))}.MixProject do
        use Mix.Project
        def project do
          [app: #{inspect(layer)}, version: "0.1.0", build_path: "../../_build",
           deps: Bilimbi.Base.ModuleRegistry.MixDiscovery.container_dependencies(__DIR__)]
        end
      end
      """)
    end
  end

  defp put_module!(root, name, dependencies) do
    layer = if name == "consumer", do: :core, else: :base
    module_root = Path.join(root, "apps/#{layer}/#{name}")
    File.mkdir_p!(Path.join(module_root, "lib"))
    namespace = Module.concat([Test, Macro.camelize(to_string(layer)), Macro.camelize(name)])
    app = String.to_atom("test_#{layer}_#{name}")

    descriptor = [
      id: "#{layer}/#{name}",
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

    File.write!(Path.join(module_root, "bilimbi.module.exs"), inspect(descriptor))

    unless File.exists?(Path.join(module_root, "mix.exs")) do
      File.write!(Path.join(module_root, "mix.exs"), """
      defmodule #{inspect(namespace)}.MixProject do
        use Mix.Project
        def project, do: Bilimbi.Base.ModuleRegistry.MixDiscovery.module_project(__DIR__, app: #{inspect(app)}, deps: [])
        def application, do: Bilimbi.Base.ModuleRegistry.MixDiscovery.module_application(__DIR__)
      end
      """)
    end
  end

  defp put_source!(root, name, source) do
    layer = if name == "consumer", do: :core, else: :base
    File.write!(Path.join(root, "apps/#{layer}/#{name}/lib/#{name}.ex"), source)
  end
end
