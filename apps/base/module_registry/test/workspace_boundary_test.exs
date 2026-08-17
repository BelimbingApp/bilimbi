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

  test "declared modules own their package, facade, descriptor, tests, and documentation" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)

    for module <- modules do
      assert File.regular?(Path.join(module.path, "mix.exs")), module.id
      assert File.regular?(Path.join(module.path, "bilimbi.module.exs")), module.id

      facade_path = Path.join([module.path, "lib", "#{Path.basename(module.path)}.ex"])
      assert File.regular?(facade_path), module.id

      assert File.dir?(Path.join(module.path, "test")), module.id
      assert File.dir?(Path.join(module.path, "docs")), module.id
      refute File.dir?(Path.join(module.path, "lib/bilimbi")), module.id

      {descriptor, _binding} = Code.eval_file(Path.join(module.path, "bilimbi.module.exs"))

      assert descriptor[:id] == module.id
      assert descriptor[:otp_app] == module.otp_app
      assert descriptor[:migrations] == module.migrations
      assert descriptor[:web] == module.web

      if module.migrations do
        assert File.dir?(Path.join(module.path, module.migrations)), module.id
      end

      if web = module.web do
        assert File.regular?(Path.join(module.path, web)), module.id
      end
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

  defp contributor_fixture?(nil), do: false

  defp contributor_fixture?(module) do
    is_binary(module.migrations) or not is_nil(module.schema_contract)
  end

  defp plural([_]), do: ""
  defp plural(_missing), do: "s"
end
