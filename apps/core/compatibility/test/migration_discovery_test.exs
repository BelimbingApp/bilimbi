defmodule Bilimbi.Core.Compatibility.MigrationDiscoveryTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Core.Compatibility

  test "resolves migrations from installed owning module descriptors" do
    migration_modules = ModuleRegistry.migration_modules!()
    migration_paths = Compatibility.migration_paths()

    # base/settings and base/session declare identical dependencies, so they
    # share a tier and the tiebreak orders them alphabetically. base/settings
    # led until it took a base/ui dependency for its group screen and joined
    # base/session's tier. Safe to reorder: neither reads the other's tables,
    # and the ascending-order assertion below is the real invariant.
    #
    # base/session then dropped below base/tenancy, base/audit and base/authz
    # when it took a base/principal_directory dependency to name users on the
    # sessions screen (#285); that seam depends on base/tenancy, so session
    # inherited the tier. Safe for the same reason, checked rather than assumed:
    # session's one migration declares no foreign key, and no other module's
    # migration references its table.
    assert Enum.map(migration_modules, & &1.id) == [
             "base/queue",
             "base/settings",
             "base/tenancy",
             "base/audit",
             "base/authz",
             "base/session",
             "core/geonames",
             "core/company",
             "core/employee",
             "core/address",
             "core/user"
           ]

    # Absolute values shift whenever any module is added ahead of these in the
    # resolved graph -- adding base/menu moved every one of them by +1, and
    # base/ui occupies a later slot among Base modules. What actually matters
    # is that the orders are strictly ascending and unique, so assert that
    # instead of pinning numbers a new module invalidates.
    orders = Enum.map(migration_modules, & &1.order)

    assert orders == Enum.sort(orders)
    assert orders == Enum.uniq(orders)

    assert migration_paths ==
             Enum.map(migration_modules, fn descriptor ->
               Application.app_dir(descriptor.otp_app, descriptor.migrations)
             end)

    assert Enum.all?(migration_paths, &File.dir?/1)

    entries = Compatibility.migration_entries()

    assert Enum.map(entries, &elem(&1, 1)) == [
             Bilimbi.Base.Session.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Base.Tenancy.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Base.Settings.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Base.Authz.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.Company.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.Company.Migrations.AddAuthzRoleCompanyConstraints,
             Bilimbi.Core.Geonames.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.Address.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.Employee.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.User.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Base.Audit.Migrations.CreateCompatibilityBaseline,
             Bilimbi.Core.Employee.Migrations.AdaptEmployeeTypesTenancyIndexes,
             Bilimbi.Core.Employee.Migrations.BroadenGlobalIndexAndAddSystemCompanyCheck,
             Bilimbi.Base.Queue.Migrations.CreateObanRuntime
           ]

    assert Enum.map(entries, &elem(&1, 2)) == [
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :compatible_baseline,
             :bilimbi_only,
             :bilimbi_only,
             :bilimbi_only
           ]

    assert Compatibility.baseline_versions() ==
             entries
             |> Enum.filter(&(elem(&1, 2) == :compatible_baseline))
             |> Enum.map(&elem(&1, 0))
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

    assert_raise ArgumentError, ~r/duplicate migration versions.*20260811093950/, fn ->
      ModuleRegistry.migration_dispositions!()
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
