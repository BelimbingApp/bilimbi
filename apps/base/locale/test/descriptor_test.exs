defmodule Bilimbi.Base.Locale.DescriptorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)

  test "is a required migration-less Settings contributor in the runtime closure" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)
    locale = Enum.find(modules, &(&1.id == "base/locale"))
    compatibility = Enum.find(modules, &(&1.id == "core/compatibility"))

    assert locale.required
    assert locale.layer == :base
    assert locale.dependencies == ["base/module_registry", "base/settings"]
    assert locale.migrations == nil
    assert locale.schema_contract == nil
    assert locale.contribution_provider == Bilimbi.Base.Locale.Contributions
    assert "base/locale" in compatibility.dependencies
  end
end
