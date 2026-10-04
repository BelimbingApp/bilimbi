defmodule BilimbiWeb.RouteAccessTest do
  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias BilimbiWeb.{RouteAccess, UserAuth}
  alias Phoenix.LiveView.Lifecycle

  defmodule GuardRouter do
    use Phoenix.Router
    import Phoenix.LiveView.Router

    live_session :guard_test do
      live("/combined", Bilimbi.Base.Dashboard.Web.IndexLive, :"bilimbi:/combined")
      live("/restricted", Bilimbi.Base.Dashboard.Web.IndexLive, :"bilimbi:/restricted")
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

  test "component events follow the destination policy after live navigation", %{conn: conn} do
    grant_capabilities!("admin.company.list")
    policies = %{@action => @policy, :"bilimbi:/restricted" => nil}
    initial = %{socket(conn) | router: GuardRouter}
    initial = Phoenix.Component.assign(initial, :live_action, :"bilimbi:/restricted")
    assert {:cont, mounted} = RouteAccess.on_mount(policies, %{}, %{}, initial)

    assert {:cont, _} =
             Lifecycle.handle_params(%{}, "http://localhost/combined", mounted)

    component = Phoenix.Component.assign(socket(conn), :current_scope, nil)
    assert {:cont, refreshed} = Bilimbi.Base.UI.EventAuthorization.authorize(component)
    assert refreshed.assigns.current_scope.actor

    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, 73, :user, 91, "admin.company.list", false)

    assert {:halt, denied} = Bilimbi.Base.UI.EventAuthorization.authorize(component)
    assert {:redirect, %{to: "/dashboard"}} = denied.redirected
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

  describe "an open page" do
    # Grants are read live, so the socket mounted before the change sees it.
    defp revoke!(capability) do
      {:ok, scope} = Tenancy.scope(41)

      {:ok, :stored} =
        Authz.put_principal_capability(scope, 73, :user, 91, capability, false)
    end

    defp decisions(capability) do
      Repo.aggregate(from(log in DecisionLog, where: log.capability == ^capability), :count)
    end

    defp mounted(conn, policies) do
      socket = %{socket(conn) | router: GuardRouter}
      assert {:cont, mounted} = RouteAccess.on_mount(policies, %{}, %{}, socket)
      mounted
    end

    test "a revoked grant refuses the next event before the view sees it", %{conn: conn} do
      grant_capabilities!("admin.user.list")
      mounted = mounted(conn, %{@action => "admin.user.list"})

      assert {:cont, _} = Lifecycle.handle_event("save", %{}, mounted)

      revoke!("admin.user.list")

      assert {:halt, denied} = Lifecycle.handle_event("save", %{}, mounted)
      assert {:redirect, %{to: "/dashboard"}} = denied.redirected
      assert denied.assigns.flash["error"] == RouteAccess.revoked_message()
    end

    test "an any-of route keeps working while either key holds", %{conn: conn} do
      grant_capabilities!("admin.user.list")
      mounted = mounted(conn, %{@action => @policy})

      revoke!("admin.user.list")
      assert {:halt, denied} = Lifecycle.handle_event("save", %{}, mounted)
      assert {:redirect, %{to: "/dashboard"}} = denied.redirected

      grant_capabilities!("admin.company.list")
      assert {:cont, _} = Lifecycle.handle_event("save", %{}, mounted)
    end

    test "a patch within the same route re-checks it, except the mount's own", %{conn: conn} do
      grant_capabilities!("admin.user.list")
      mounted = mounted(conn, %{@action => "admin.user.list"})
      after_mount = decisions("admin.user.list")

      assert {:cont, routed} =
               Lifecycle.handle_params(%{}, "http://localhost/combined", mounted)

      assert decisions("admin.user.list") == after_mount

      assert {:cont, _} =
               Lifecycle.handle_params(%{"page" => "2"}, "http://localhost/combined", routed)

      assert decisions("admin.user.list") == after_mount + 1

      revoke!("admin.user.list")

      assert {:halt, denied} =
               Lifecycle.handle_params(%{"page" => "3"}, "http://localhost/combined", routed)

      assert {:redirect, %{to: "/dashboard"}} = denied.redirected
      assert denied.assigns.flash["error"] == RouteAccess.revoked_message()
    end

    test "a terminated session ends the page at its next event or patch", %{conn: conn} do
      grant_capabilities!("admin.user.list")
      mounted = mounted(conn, %{@action => "admin.user.list"})
      assert {:cont, routed} = Lifecycle.handle_params(%{}, "http://localhost/combined", mounted)

      :ok = Session.delete_session(mounted.assigns.current_scope.session_identity["session_id"])

      assert {:halt, ended} = Lifecycle.handle_event("save", %{}, routed)
      assert {:redirect, %{to: "/"}} = ended.redirected
      assert ended.assigns.flash["session_expired"] == "expired"

      assert {:halt, ended} =
               Lifecycle.handle_params(%{"page" => "2"}, "http://localhost/combined", routed)

      assert {:redirect, %{to: "/"}} = ended.redirected
    end

    test "an event carries the refreshed capability list", %{conn: conn} do
      grant_capabilities!(["admin.user.list", "admin.user.view"])
      mounted = mounted(conn, %{@action => "admin.user.list"})
      refute "admin.user.view" in mounted.assigns.current_scope.capabilities

      assert {:cont, refreshed} = Lifecycle.handle_event("save", %{}, mounted)
      assert "admin.user.view" in refreshed.assigns.current_scope.capabilities

      revoke!("admin.user.view")

      assert {:cont, refreshed} = Lifecycle.handle_event("save", %{}, refreshed)
      refute "admin.user.view" in refreshed.assigns.current_scope.capabilities
    end

    test "each event costs one decision per key and nothing on an ungated route", %{conn: conn} do
      grant_capabilities!("admin.user.list")
      mounted = mounted(conn, %{@action => "admin.user.list"})
      after_mount = decisions("admin.user.list")

      assert {:cont, _} = Lifecycle.handle_event("save", %{}, mounted)
      assert decisions("admin.user.list") == after_mount + 1

      ungated = mounted(conn, %{@action => nil})
      total = Repo.aggregate(DecisionLog, :count)

      revoke!("admin.user.list")

      assert {:cont, _} = Lifecycle.handle_event("save", %{}, ungated)
      assert {:cont, _} = Lifecycle.handle_params(%{}, "http://localhost/combined", ungated)
      assert Repo.aggregate(DecisionLog, :count) == total
    end
  end

  test "presentation checks either key and refuses neither" do
    for grant <- ["admin.user.list", "admin.company.list"] do
      assert Bilimbi.Base.UI.allowed?(%{capabilities: [grant]}, @policy)
    end

    refute Bilimbi.Base.UI.allowed?(%{capabilities: []}, @policy)
    refute Bilimbi.Base.UI.allowed?(nil, @policy)
  end
end
