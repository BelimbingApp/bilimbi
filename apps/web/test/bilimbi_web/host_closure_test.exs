defmodule BilimbiWeb.HostClosureTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)

  test "the host runtime loads every module of the discovered graph" do
    discovered =
      @workspace_root
      |> MixDiscovery.discover_workspace!()
      |> Enum.map(& &1.id)

    assert Enum.map(ModuleRegistry.complete_modules!(), & &1.id) == discovered
  end
end
