defmodule BilimbiWeb.DiscoveredRoutesTest do
  use ExUnit.Case, async: true

  alias BilimbiWeb.DiscoveredRoutes

  test "module_routes/1 drops host-owned routes" do
    routes = [
      %{path: "/widgets", live: Foo, source: "core/foo"},
      %{path: "/", live: BilimbiWeb.LoginLive, source: "web"}
    ]

    assert DiscoveredRoutes.module_routes(routes) == [
             %{path: "/widgets", live: Foo, source: "core/foo"}
           ]
  end

  test "router includes tenant and session admin routes from the test-env manifest" do
    paths = BilimbiWeb.Router.__routes__() |> Enum.map(& &1.path)
    assert "/tenancy/tenants" in paths
    assert "/system/sessions" in paths
  end
end
