defmodule Bilimbi.Base.ModuleRegistry.WorkspaceBoundaryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)
  @base_root Path.join(@workspace_root, "apps/base")
  @core_root Path.join(@workspace_root, "apps/core")

  @modules [
    %{
      root: Path.join(@base_root, "database"),
      id: "base/database",
      app: :bilimbi_base_database,
      facade: "lib/database.ex",
      migrations: nil
    },
    %{
      root: Path.join(@base_root, "module_registry"),
      id: "base/module_registry",
      app: :bilimbi_base_module_registry,
      facade: "lib/module_registry.ex",
      migrations: nil
    },
    %{
      root: Path.join(@base_root, "tenancy"),
      id: "base/tenancy",
      app: :bilimbi_base_tenancy,
      facade: "lib/tenancy.ex",
      migrations: "priv/repo/migrations"
    },
    %{
      root: Path.join(@core_root, "company"),
      id: "core/company",
      app: :bilimbi_core_company,
      facade: "lib/company.ex",
      migrations: "priv/repo/migrations"
    },
    %{
      root: Path.join(@core_root, "employee"),
      id: "core/employee",
      app: :bilimbi_core_employee,
      facade: "lib/employee.ex",
      migrations: "priv/repo/migrations"
    },
    %{
      root: Path.join(@core_root, "geonames"),
      id: "core/geonames",
      app: :bilimbi_core_geonames,
      facade: "lib/geonames.ex",
      migrations: "priv/repo/migrations"
    },
    %{
      root: Path.join(@core_root, "address"),
      id: "core/address",
      app: :bilimbi_core_address,
      facade: "lib/address.ex",
      migrations: "priv/repo/migrations"
    },
    %{
      root: Path.join(@core_root, "compatibility"),
      id: "core/compatibility",
      app: :bilimbi_core_compatibility,
      facade: "lib/compatibility.ex",
      migrations: nil
    }
  ]

  test "composition containers contain no module implementation or resources" do
    for container_root <- [@base_root, @core_root] do
      refute File.dir?(Path.join(container_root, "lib"))
      refute File.dir?(Path.join(container_root, "priv"))
      refute File.dir?(Path.join(container_root, "test"))
    end
  end

  test "declared modules own their package, facade, descriptor, tests, and documentation" do
    for module <- @modules do
      assert File.regular?(Path.join(module.root, "mix.exs")), module.id
      assert File.regular?(Path.join(module.root, "bilimbi.module.exs")), module.id
      assert File.regular?(Path.join(module.root, module.facade)), module.id
      assert File.dir?(Path.join(module.root, "test")), module.id
      assert File.dir?(Path.join(module.root, "docs")), module.id
      refute File.dir?(Path.join(module.root, "lib/bilimbi")), module.id

      {descriptor, _binding} = Code.eval_file(Path.join(module.root, "bilimbi.module.exs"))

      assert descriptor[:id] == module.id
      assert descriptor[:otp_app] == module.app
      assert descriptor[:migrations] == module.migrations

      if module.migrations do
        assert File.dir?(Path.join(module.root, module.migrations)), module.id
      end
    end
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
        refute mix_source =~ Path.basename(module.path)
      end
    end
  end
end
