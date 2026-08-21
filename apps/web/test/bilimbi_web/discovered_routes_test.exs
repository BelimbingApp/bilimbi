defmodule BilimbiWeb.DiscoveredRoutesTest do
  use ExUnit.Case, async: true

  alias BilimbiWeb.DiscoveredRoutes

  @user_routes [
    {"/users", "/users", Bilimbi.Core.UserAdministration.Web.IndexLive},
    {"/users/new", "/users/new", Bilimbi.Core.User.Web.FormLive},
    {"/users/:id", "/users/91", Bilimbi.Core.User.Web.ShowLive},
    {"/users/:id/edit", "/users/91/edit", Bilimbi.Core.User.Web.FormLive}
  ]

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

  test "keeps the User Administration index contribution for discovered injection" do
    routes = [
      %{
        path: "/users",
        live: Bilimbi.Core.UserAdministration.Web.IndexLive,
        source: "core/user_administration"
      },
      %{path: "/", live: BilimbiWeb.LoginLive, source: "web"}
    ]

    assert DiscoveredRoutes.module_routes(routes) == [
             %{
               path: "/users",
               live: Bilimbi.Core.UserAdministration.Web.IndexLive,
               source: "core/user_administration"
             }
           ]
  end

  test "does not retain host registrations for module-owned user paths" do
    {host_routes, _binding} = Code.eval_file(Path.expand("../../priv/web_routes.exs", __DIR__))

    {user_routes, _binding} =
      Code.eval_file(Path.expand("../../../core/user/priv/web_routes.exs", __DIR__))

    {administration_routes, _binding} =
      Code.eval_file(
        Path.expand("../../../core/user_administration/priv/web_routes.exs", __DIR__)
      )

    host_paths = MapSet.new(host_routes, & &1.path)
    module_paths = MapSet.new(user_routes ++ administration_routes, & &1.path)

    assert MapSet.disjoint?(host_paths, module_paths)
  end

  test "router reaches the transferred index and three retained User routes exactly once" do
    registered_routes = BilimbiWeb.Router.__routes__()

    Enum.each(@user_routes, fn {route_path, request_path, live_view} ->
      assert Enum.count(registered_routes, &(&1.path == route_path)) == 1

      assert %{
               plug: Phoenix.LiveView.Plug,
               phoenix_live_view: {^live_view, _action, _options, _live_session}
             } = Phoenix.Router.route_info(BilimbiWeb.Router, "GET", request_path, "localhost")
    end)
  end

  test "route manifest records the exact atomic ownership transfer" do
    routes = manifest_routes()

    assert Enum.count(routes, fn route ->
             route.path == "/users" and route.source == "core/user_administration" and
               route.live == Bilimbi.Core.UserAdministration.Web.IndexLive
           end) == 1

    assert Enum.count(routes, &(&1.path == "/users")) == 1

    for path <- ["/users/new", "/users/:id", "/users/:id/edit"] do
      assert Enum.count(routes, &(&1.path == path and &1.source == "core/user")) == 1
    end
  end

  test "Core User menu and capability contribution still targets the transferred route" do
    contributions = Bilimbi.Core.User.Contributions.contributions()

    assert %{route: "/users", capability: "admin.user.list"} =
             Enum.find(contributions.menu, &(&1.id == "admin.user"))

    assert "admin.user.list" in contributions.authz.capabilities
  end

  defp manifest_routes do
    manifest = Path.expand("../../../../_build/test/bilimbi_routes.exs", __DIR__)
    {entries, _binding} = Code.eval_file(manifest)
    # The manifest also carries embed entries; these assertions are about routes.
    Enum.filter(entries, &Map.has_key?(&1, :path))
  end
end
