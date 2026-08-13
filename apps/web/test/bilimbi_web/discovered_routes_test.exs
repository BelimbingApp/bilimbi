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
end
