defmodule Bilimbi.Base.ModuleRegistry.WorkspaceBoundaryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)
  @base_root Path.join(@workspace_root, "apps/base")
  @core_root Path.join(@workspace_root, "apps/core")

  test "composition containers contain no module implementation or resources" do
    assert container_resources(@workspace_root) == []
  end

  test "a mounted container carrying its own lib/ fails the container check" do
    root = mounted_container_lib_workspace!()
    on_exit(fn -> File.rm_rf!(root) end)

    assert_raise ArgumentError, ~r{apps/domains/factory/lib is missing bilimbi.module.exs}, fn ->
      container_resources(root)
    end
  end

  test "discovery finds exactly the modules installed on disk" do
    discovered =
      @workspace_root
      |> MixDiscovery.discover_workspace!()
      |> Enum.map(& &1.path)
      |> Enum.sort()

    on_disk = module_roots_on_disk()

    refute on_disk == [],
           "no bilimbi.module.exs found under any composition container"

    assert discovered == on_disk
  end

  # Descriptor shape and declared path safety are enforced by discovery. The
  # missing migration directory regression below proves that path existence
  # fails closed before this loop can inspect installed modules.
  test "installed modules own their package, facade, tests, and documentation" do
    for module <- MixDiscovery.discover_workspace!(@workspace_root) do
      facade = Path.join("lib", Path.basename(module.path) <> ".ex")

      assert File.regular?(Path.join(module.path, "mix.exs")), module.id
      assert File.regular?(Path.join(module.path, facade)), "#{module.id}: #{facade}"
      assert File.dir?(Path.join(module.path, "test")), module.id
      assert File.dir?(Path.join(module.path, "docs")), module.id
      refute File.dir?(Path.join(module.path, "lib/bilimbi")), module.id
    end
  end

  test "discovery rejects a safe missing migration directory" do
    root = missing_migration_workspace!()
    on_exit(fn -> File.rm_rf!(root) end)

    assert_raise ArgumentError, ~r/declared migration directory does not exist/, fn ->
      MixDiscovery.discover_workspace!(root)
    end
  end

  # The host's OTP closure must be the whole graph: Web depends on the Base
  # and Core umbrella siblings and on every mounted container, and each
  # container depends on its own modules. `ModuleRegistry.complete_modules!/0`
  # enforces the same at host boot.
  test "the Web host's container closure reaches every discovered module" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)
    web_root = Path.join(@workspace_root, "apps/web")

    mounted_roots =
      web_root
      |> MixDiscovery.optional_container_dependencies()
      |> Enum.map(fn {_app, path: path} -> Path.expand(path, web_root) end)

    host_apps =
      [@base_root, @core_root | mounted_roots]
      |> Enum.flat_map(&MixDiscovery.container_dependencies/1)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    assert host_apps == modules |> Enum.map(& &1.otp_app) |> Enum.sort()
  end

  test "Base and Core compose immediate child modules without naming them" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)

    for container_root <- [@base_root, @core_root] do
      container_modules = Enum.filter(modules, &(&1.container_path == container_root))
      dependencies = MixDiscovery.container_dependencies(container_root)

      assert Enum.map(dependencies, &elem(&1, 0)) ==
               Enum.map(container_modules, & &1.otp_app)

      mix_source = File.read!(Path.join(container_root, "mix.exs"))

      for module <- container_modules do
        refute mix_source =~ Atom.to_string(module.otp_app)
        refute mix_source =~ ~s("#{Path.basename(module.path)}")
      end
    end
  end

  test ".gitignore ignores deps, _build, and build artifacts without trailing slash restriction" do
    gitignore =
      @workspace_root
      |> Path.join(".gitignore")
      |> File.read!()
      |> String.replace("\r\n", "\n")

    for path <- ~w(/_build /deps /cover /doc /tmp /.elixir_ls) do
      assert gitignore =~ "\n#{path}\n" or gitignore =~ "#{path}\n",
             "expected #{path} to be ignored without a trailing slash"

      refute gitignore =~ "#{path}/\n",
             "expected #{path} not to have a trailing slash restricting it to directories only"
    end
  end

  # Base and Core containers sit directly under apps/; mounted Domain and
  # Extension repositories sit one level deeper.
  defp module_roots_on_disk do
    ["apps/*/bilimbi.container.exs", "apps/{domains,extensions}/*/bilimbi.container.exs"]
    |> Enum.flat_map(&Path.wildcard(Path.join(@workspace_root, &1)))
    |> Enum.map(&Path.dirname/1)
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*/bilimbi.module.exs")))
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  defp container_resources(workspace_root) do
    for container_root <- MixDiscovery.container_paths(workspace_root),
        directory <- ~w(lib priv test),
        path = Path.join(container_root, directory),
        File.dir?(path),
        do: path
  end

  defp mounted_container_lib_workspace! do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-workspace-boundary-#{System.unique_integer([:positive, :monotonic])}"
      )

    container = Path.join([root, "apps", "domains", "factory"])
    module = Path.join(container, "widget")

    File.mkdir_p!(module)
    File.mkdir_p!(Path.join(container, "lib"))
    {_, 0} = System.cmd("git", ["init", "-q", container])

    File.write!(
      Path.join(container, "bilimbi.container.exs"),
      inspect([id: "factory", kind: :container, layer: :domain], pretty: true) <> "\n"
    )

    descriptor = [
      id: "factory/widget",
      kind: :module,
      layer: :domain,
      required: false,
      otp_app: :test_boundary_factory_widget,
      namespace: Test.Boundary.Factory.Widget,
      dependencies: [],
      migrations: nil,
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(
      Path.join(module, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )

    root
  end

  defp missing_migration_workspace! do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-workspace-boundary-#{System.unique_integer([:positive, :monotonic])}"
      )

    container = Path.join([root, "apps", "base"])
    module = Path.join([container, "database"])

    File.mkdir_p!(module)

    File.write!(
      Path.join(container, "bilimbi.container.exs"),
      inspect([id: "base", kind: :container, layer: :base], pretty: true) <> "\n"
    )

    descriptor = [
      id: "base/database",
      kind: :module,
      layer: :base,
      required: true,
      otp_app: :test_boundary_database,
      namespace: Test.Boundary.Database,
      dependencies: [],
      migrations: "priv/repo/migrations",
      migration_dispositions: %{20_260_817_000_001 => :compatible_baseline},
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(
      Path.join(module, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )

    root
  end
end
