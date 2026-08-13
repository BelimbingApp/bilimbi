defmodule Bilimbi.Core.Compatibility.MigrationDiscoveryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Core.Compatibility

  test "resolves migrations from installed owning module descriptors" do
    migration_modules = ModuleRegistry.migration_modules!()
    migration_paths = Compatibility.migration_paths()

    assert Enum.map(migration_modules, & &1.id) == [
             "base/session",
             "base/settings",
             "base/tenancy",
             "base/audit",
             "base/authz",
             "core/company",
             "core/employee",
             "core/geonames",
             "core/address",
             "core/user"
           ]

    assert Enum.map(migration_modules, & &1.order) == [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

    assert migration_paths ==
             Enum.map(migration_modules, fn descriptor ->
               Application.app_dir(descriptor.otp_app, descriptor.migrations)
             end)

    assert Enum.all?(migration_paths, &File.dir?/1)

    assert Enum.map(Compatibility.migration_entries(), &elem(&1, 1)) == [
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
             Bilimbi.Base.Audit.Migrations.CreateCompatibilityBaseline
           ]
  end
end
