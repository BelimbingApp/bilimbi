defmodule Bilimbi.Base.ModuleRegistry.WorkspaceBoundaryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)
  @base_root Path.join(@workspace_root, "apps/base")
  @core_root Path.join(@workspace_root, "apps/core")

  test "composition containers contain no module implementation or resources" do
    for container_root <- [@base_root, @core_root] do
      refute File.dir?(Path.join(container_root, "lib"))
      refute File.dir?(Path.join(container_root, "priv"))
      refute File.dir?(Path.join(container_root, "test"))
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

  test "Compatibility's runtime closure includes every migration or schema-contract contributor" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)
    missing = MixDiscovery.missing_compatibility_contributors(modules)

    assert missing == [],
           "Compatibility runtime closure is missing contributor#{plural(missing)} #{Enum.join(missing, ", ")}"
  end

  test "removing core/user from Compatibility's dependencies fails naming core/user" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)
    user = Enum.find(modules, &(&1.id == "core/user"))

    assert contributor_fixture?(user),
           "core/user must still declare migrations or a schema_contract"

    compatibility = Enum.find(modules, &(&1.id == "core/compatibility"))
    omitted = List.delete(compatibility.dependencies, "core/user")
    missing = MixDiscovery.missing_compatibility_contributors(modules, omitted)

    assert "core/user" in missing

    message =
      "Compatibility runtime closure is missing contributor#{plural(missing)} #{Enum.join(missing, ", ")}"

    assert message =~ "core/user"
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

  defp module_roots_on_disk do
    @workspace_root
    |> Path.join("apps/*/bilimbi.container.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*/bilimbi.module.exs")))
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
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
      contribution_provider: nil
    ]

    File.write!(
      Path.join(module, "bilimbi.module.exs"),
      inspect(descriptor, pretty: true, limit: :infinity) <> "\n"
    )

    root
  end

  defp contributor_fixture?(nil), do: false

  defp contributor_fixture?(module) do
    is_binary(module.migrations) or not is_nil(module.schema_contract)
  end

  defp plural([_]), do: ""
  defp plural(_missing), do: "s"
end
