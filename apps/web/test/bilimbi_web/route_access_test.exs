defmodule BilimbiWeb.RouteAccessTest do
  use BilimbiWeb.ConnCase, async: false

  alias BilimbiWeb.{RouteAccess, UserAuth}
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  defmodule GuardRouter do
    use Phoenix.Router
    import Phoenix.LiveView.Router

    live_session :guard_test do
      live "/combined", BilimbiWeb.DashboardLive, :"bilimbi:/combined"
      live "/restricted", BilimbiWeb.DashboardLive, :"bilimbi:/restricted"
    end
  end

  @policy {:any_of, ["admin.user.list", "admin.company.list"]}
  @action :"bilimbi:/combined"

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    conn = conn |> log_in_as() |> fetch_flash() |> UserAuth.fetch_current_scope([])
    %{conn: conn}
  end

  defp socket(conn) do
    %Phoenix.LiveView.Socket{
      router: BilimbiWeb.Router,
      assigns: %{
        __changed__: %{},
        flash: %{},
        live_action: @action,
        current_scope: conn.assigns.current_scope
      },
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end

  for grant <- ["admin.user.list", "admin.company.list"] do
    test "either grant allows the route and controller guard: #{grant}", %{conn: conn} do
      grant_capabilities!(unquote(grant))
      # The guard asks Authz live: this scope was hydrated before the grant.
      assert {:cont, mounted} =
               RouteAccess.on_mount(%{@action => @policy}, %{}, %{}, socket(conn))

      assert mounted.assigns.live_action == nil
      refute UserAuth.require_capability(conn, @policy).halted
    end
  end

  test "no matching grant refuses both guards even with stale UI allows", %{conn: conn} do
    grant_capabilities!("admin.user.view")

    conn =
      assign(
        conn,
        :current_scope,
        Map.put(conn.assigns.current_scope, :capabilities, ["admin.company.list"])
      )

    assert {:halt, denied} = RouteAccess.on_mount(%{@action => @policy}, %{}, %{}, socket(conn))
    assert {:redirect, %{to: "/dashboard"}} = denied.redirected
    assert redirected_to(UserAuth.require_capability(conn, @policy)) == "/dashboard"
  end

  test "the single-capability form still asks Authz live", %{conn: conn} do
    assert {:halt, _} =
             RouteAccess.on_mount(%{@action => "admin.user.list"}, %{}, %{}, socket(conn))

    grant_capabilities!("admin.user.list")

    assert {:cont, _} =
             RouteAccess.on_mount(%{@action => "admin.user.list"}, %{}, %{}, socket(conn))

    refute UserAuth.require_capability(conn, "admin.user.list").halted
  end

  test "patching to an any-of route checks the destination policy", %{conn: conn} do
    policies = %{@action => @policy, :"bilimbi:/restricted" => nil}
    initial = %{socket(conn) | router: GuardRouter}
    initial = Phoenix.Component.assign(initial, :live_action, :"bilimbi:/restricted")
    assert {:cont, mounted} = RouteAccess.on_mount(policies, %{}, %{}, initial)

    assert {:halt, denied} =
             Phoenix.LiveView.Lifecycle.handle_params(%{}, "http://localhost/combined", mounted)

    assert {:redirect, %{to: "/dashboard"}} = denied.redirected

    grant_capabilities!("admin.company.list")

    assert {:cont, patched} =
             Phoenix.LiveView.Lifecycle.handle_params(%{}, "http://localhost/combined", mounted)

    assert patched.assigns.live_action == nil
    assert patched.private.bilimbi_route_action == @action
  end

  test "presentation checks either key and refuses neither" do
    for grant <- ["admin.user.list", "admin.company.list"] do
      assert Bilimbi.Base.UI.allowed?(%{capabilities: [grant]}, @policy)
    end

    refute Bilimbi.Base.UI.allowed?(%{capabilities: []}, @policy)
    refute Bilimbi.Base.UI.allowed?(nil, @policy)
  end
end
