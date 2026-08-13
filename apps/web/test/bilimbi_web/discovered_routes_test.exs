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

  test "keeps the Core User route contribution for discovered injection" do
    routes = [
      %{path: "/users", live: Bilimbi.Core.User.Web.IndexLive, source: "core/user"},
      %{path: "/", live: BilimbiWeb.LoginLive, source: "web"}
    ]

    assert DiscoveredRoutes.module_routes(routes) == [
             %{path: "/users", live: Bilimbi.Core.User.Web.IndexLive, source: "core/user"}
           ]
  end

  test "does not retain host registrations for module-owned user paths" do
    {host_routes, _binding} = Code.eval_file(Path.expand("../../priv/web_routes.exs", __DIR__))

    {user_routes, _binding} =
      Code.eval_file(Path.expand("../../../core/user/priv/web_routes.exs", __DIR__))

    host_paths = MapSet.new(host_routes, & &1.path)

    assert MapSet.disjoint?(host_paths, MapSet.new(user_routes, & &1.path))
  end
end
