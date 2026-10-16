defmodule Bilimbi.Core.Compatibility.MigrationDiscoveryTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Core.Compatibility

  test "resolves migrations from installed owning module descriptors" do
    expected = ModuleRegistry.installed_modules!() |> Enum.reject(&is_nil(&1.migrations))
    migration_modules = ModuleRegistry.migration_modules!()
    migration_paths = Compatibility.migration_paths()
    assert Enum.map(migration_modules, & &1.id) == Enum.map(expected, & &1.id)
    orders = Enum.map(migration_modules, & &1.order)
    assert orders == Enum.sort(orders)
    assert orders == Enum.uniq(orders)
    assert migration_paths == Enum.map(expected, &Application.app_dir(&1.otp_app, &1.migrations))
    assert Enum.all?(migration_paths, &File.dir?/1)

    # Ownership and dispositions come from the installed descriptors. A pinned
    # contributor/module list is a second registry and fails on every addition.
    entries = Compatibility.migration_entries()

    expected_versions =
      expected |> Enum.flat_map(&Map.to_list(&1.migration_dispositions)) |> Enum.sort()

    assert Enum.map(entries, fn {version, _module, disposition} -> {version, disposition} end) ==
             expected_versions

    for {version, module, _disposition} <- entries do
      owner = Enum.find(expected, &Map.has_key?(&1.migration_dispositions, version))
      assert String.starts_with?(Atom.to_string(module), Atom.to_string(owner.namespace) <> ".")
      assert function_exported?(module, :__migration__, 0)
    end

    assert Compatibility.baseline_versions() ==
             for({version, :compatible_baseline} <- expected_versions, do: version)
  end

  test "runtime rejects missing, unknown, and non-exact migration dispositions" do
    {_path, descriptor} = put_test_migration!(20_260_814_120_000)

    Application.put_env(
      :bilimbi_core_compatibility,
      :bilimbi_module,
      Map.delete(descriptor, :migration_dispositions)
    )

    assert_raise ArgumentError, ~r/invalid migration_dispositions metadata/, fn ->
      ModuleRegistry.installed_modules!()
    end

    Application.put_env(
      :bilimbi_core_compatibility,
      :bilimbi_module,
      put_in(descriptor.migration_dispositions[20_260_814_120_000], :unknown)
    )

    assert_raise ArgumentError, ~r/invalid migration_dispositions metadata/, fn ->
      ModuleRegistry.installed_modules!()
    end

    Application.put_env(
      :bilimbi_core_compatibility,
      :bilimbi_module,
      %{descriptor | migration_dispositions: %{20_260_814_120_001 => :bilimbi_only}}
    )

    assert_raise ArgumentError, ~r/do not match migration files/, fn ->
      ModuleRegistry.installed_modules!()
    end

    Application.put_env(
      :bilimbi_core_compatibility,
      :bilimbi_module,
      %{descriptor | migrations: "../outside"}
    )

    assert_raise ArgumentError, ~r/unsafe migration path/, fn ->
      ModuleRegistry.installed_modules!()
    end
  end

  test "runtime rejects duplicate migration versions globally" do
    {_path, _descriptor} = put_test_migration!(20_260_811_093_950)

    assert_raise ArgumentError,
                 ~r/duplicate migration versions: 20260811093950 \(.*core\/compatibility.*\)/,
                 fn -> ModuleRegistry.migration_dispositions!() end
  end

  test "runtime accepts a renumbering only from an unshipped version to a shipped one" do
    version = 20_260_814_120_000
    {_path, descriptor} = put_test_migration!(version)
    app = :bilimbi_core_compatibility

    Application.put_env(
      app,
      :bilimbi_module,
      Map.put(descriptor, :renumbered_migrations, %{20_260_814_110_000 => version})
    )

    assert Enum.any?(ModuleRegistry.migration_modules!(), &(&1.id == descriptor.id))

    for invalid <- [%{version => version}, %{20_260_814_110_000 => 20_260_814_130_000}, %{}] do
      Application.put_env(
        app,
        :bilimbi_module,
        Map.put(descriptor, :renumbered_migrations, invalid)
      )

      assert_raise ArgumentError, ~r/invalid renumbered_migrations metadata/, fn ->
        ModuleRegistry.installed_modules!()
      end
    end
  end

  test "runtime rejects compiled graph drift before exposing migrations" do
    app = :bilimbi_core_compatibility
    descriptor = Application.fetch_env!(app, :bilimbi_module)

    Application.put_env(
      app,
      :bilimbi_module,
      %{descriptor | graph_fingerprint: "test-graph-drift"}
    )

    on_exit(fn -> Application.put_env(app, :bilimbi_module, descriptor) end)

    assert_raise ArgumentError, ~r/compiled from different workspace graphs/, fn ->
      ModuleRegistry.migration_modules!()
    end
  end

  defp put_test_migration!(version) do
    app = :bilimbi_core_compatibility
    descriptor = Application.fetch_env!(app, :bilimbi_module)
    relative_path = "test_migrations_#{System.unique_integer([:positive, :monotonic])}"
    path = Application.app_dir(app, relative_path)
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "#{version}_test_migration.exs"),
      "defmodule RuntimeMetadataTestMigration do\nend\n"
    )

    test_descriptor =
      descriptor
      |> Map.put(:migrations, relative_path)
      |> Map.put(:migration_dispositions, %{version => :bilimbi_only})

    Application.put_env(app, :bilimbi_module, test_descriptor)

    on_exit(fn ->
      Application.put_env(app, :bilimbi_module, descriptor)
      File.rm_rf!(path)
    end)

    {path, test_descriptor}
  end
end
