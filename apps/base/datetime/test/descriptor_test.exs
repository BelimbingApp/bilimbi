defmodule Bilimbi.Base.DateTime.DescriptorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)

  test "is a required migration-less Settings contributor in the runtime closure" do
    modules = MixDiscovery.discover_workspace!(@workspace_root)
    datetime = Enum.find(modules, &(&1.id == "base/datetime"))
    compatibility = Enum.find(modules, &(&1.id == "core/compatibility"))

    assert datetime.required
    assert datetime.layer == :base

    assert datetime.dependencies == [
             "base/locale",
             "base/module_registry",
             "base/settings",
             "base/ui"
           ]

    assert datetime.migrations == nil
    assert datetime.schema_contract == nil
    assert datetime.contribution_provider == Bilimbi.Base.DateTime.Contributions
    assert "base/datetime" in compatibility.dependencies
  end
end
