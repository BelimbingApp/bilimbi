defmodule BilimbiWeb.DashboardLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    {:ok, scope} = Tenancy.scope(41)
    {:ok, scope: scope}
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "shows the workspace identity and real counts", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#app-tenant", "41")
    assert has_element?(view, "#stat-companies", "1")
    assert has_element?(view, "#stat-users", "1")

    assert has_element?(
             view,
             "#dashboard-current-company[data-company-id='73']"
           )

    assert has_element?(view, "#dashboard-company-name", "Bilimbi Industries")
  end

  test "lists users affiliated with the tenant's companies", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#dashboard-users")
    assert has_element?(view, "#dashboard-user-91 td", "Ada Lovelace")
  end

  test "renders the sidebar without gated destinations when capabilities are absent", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "#app-topbar")
    assert has_element?(view, "#app-sidebar-toggle[aria-controls='app-sidebar']")
    assert has_element?(view, "#app-brand[href='/dashboard']", "Bilimbi")
    refute has_element?(view, "#app-dev")
    refute has_element?(view, "#app-env")
    refute has_element?(view, "#app-debug")
    assert has_element?(view, "#app-statusbar")

    version = Application.get_env(:bilimbi_base_ui, :app_version, "0.1.0")
    assert has_element?(view, "#app-version", "v#{version}")
    assert has_element?(view, "#app-topbar-main")
    assert has_element?(view, "#app-shell[phx-hook='AppShell']")
    assert has_element?(view, "#app-sidebar-drag")
    refute has_element?(view, "#nav-dashboard")
    assert has_element?(view, "#app-nav-empty")
    refute has_element?(view, "#nav-admin-company")
    refute has_element?(view, "#nav-admin-user")
    refute has_element?(view, "#dashboard-company-open")
    assert has_element?(view, "#app-user-name", "Ada Lovelace")
    assert has_element?(view, "#app-logout")
  end

  test "shows companies and users navigation when those capabilities are granted", %{conn: conn} do
    grant_capabilities!(["admin.company.list", "admin.company.view", "admin.user.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#nav-admin-company")
    assert has_element?(view, "#nav-admin-user")
    assert has_element?(view, "#nav-branch-admin[data-nav-default-expanded='false']")

    assert has_element?(
             view,
             "#nav-toggle-admin[aria-controls='nav-children-admin'][aria-expanded='false']"
           )

    assert has_element?(view, "#nav-children-admin[hidden]")
    assert has_element?(view, "#nav-admin-company[data-nav-item='nav-admin-company']")
    assert has_element?(view, "#nav-pin-admin-company[data-nav-pin='nav-admin-company']")
    assert has_element?(view, "#app-pinned[hidden]")

    # A LiveView marks itself current by naming its menu item. Nothing else
    # connects the two, so a screen naming an id the menu does not define
    # highlights nothing -- and the sidebar looks fine while it happens.
    refute has_element?(view, "#nav-dashboard")
    refute has_element?(view, "#app-nav-empty")
    refute has_element?(view, "#nav-admin-company[aria-current='page']")
    assert has_element?(view, "#dashboard-company-open")
    assert has_element?(view, "#stat-companies[href='/companies']")
    assert has_element?(view, "#stat-users[href='/users']")
  end

  test "drops authentication when the live user is gone", %{conn: conn} do
    conn = log_in_as(conn)
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DELETE FROM users WHERE id = 91", [])

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "drops authentication when the durable session is terminated", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    :ok = Session.delete_session(session_id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  describe "widget capability isolation" do
    test "unprivileged user sees only ungated widgets and cannot see gated widgets in available list",
         %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      refute has_element?(view, "#stat-recent-audit")

      # Enter edit mode
      view |> element("#edit-layout") |> render_click()

      # Gated widgets are not in available list
      refute has_element?(view, "#add-widget-base-dashboard-recent-audit")
    end

    test "denies unauthorized add-widget event bypass", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      # Attempt to add gated widget directly via event
      render_click(view, "add-widget", %{"id" => "base-dashboard-recent-audit"})

      # Widget must not be added
      refute has_element?(view, "#stat-recent-audit")
    end

    test "handles unknown/forged widget id safely without crashing", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      render_click(view, "add-widget", %{"id" => "forged-unknown-widget"})
      render_click(view, "remove-widget", %{"id" => "forged-unknown-widget"})
      render_click(view, "move-up", %{"id" => "forged-unknown-widget"})
      render_click(view, "move-down", %{"id" => "forged-unknown-widget"})

      # View remains alive and responsive
      assert has_element?(view, "#stat-companies")
    end

    test "shows gated widgets when corresponding capabilities are granted", %{conn: conn} do
      grant_capabilities!(["admin.audit.log.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      assert has_element?(view, "#stat-recent-audit")
      assert render(view) =~ "No recent activity."
    end

    test "renders live audit mutation entries in recent activity widget", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!(["admin.audit.log.list"])

      {:ok, mutation} =
        Audit.record_mutation(scope, %{
          actor_type: "user",
          actor_id: 91,
          auditable_type: "Company",
          auditable_id: "73",
          event: "created",
          source: "listener",
          occurred_at: NaiveDateTime.utc_now()
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-recent-audit")
      refute render(view) =~ "No recent activity."
      assert has_element?(view, "#audit-entry-#{mutation.id}")
      assert render(view) =~ "created"
      assert render(view) =~ "Company"
    end

    test "session widget stays hidden without admin.system.session.list", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      refute has_element?(view, "#stat-sessions")

      # Not offered for adding either.
      view |> element("#edit-layout") |> render_click()
      refute has_element?(view, "#add-widget-base-dashboard-session-stats")
    end

    test "session widget counts durable sessions behind its capability", %{conn: conn} do
      grant_capabilities!(["admin.system.session.list"])

      # The viewer's own durable session already contributes at least one row;
      # add two more so the count is unambiguous.
      Session.put_session("dash-extra-a", "opaque", %{
        user_id: 91,
        ip_address: "127.0.0.1",
        user_agent: "Bilimbi test",
        last_activity: 100
      })

      Session.put_session("dash-extra-b", "opaque", %{
        user_id: 91,
        ip_address: "127.0.0.2",
        user_agent: "Bilimbi test",
        last_activity: 200
      })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-sessions")
      assert has_element?(view, "#stat-sessions", "3")
    end
  end

  describe "widget layout customization and persistence" do
    test "removes and re-adds widgets, persisting layout to settings", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      # Enter edit mode
      view |> element("#edit-layout") |> render_click()
      assert has_element?(view, "#done-layout")

      # Remove companies widget
      view |> element("#remove-base-dashboard-company-stats") |> render_click()

      refute has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      assert has_element?(view, "#add-widget-base-dashboard-company-stats")

      # Add it back
      view |> element("#add-widget-base-dashboard-company-stats") |> render_click()

      assert has_element?(view, "#stat-companies")
      refute has_element?(view, "#add-widget-base-dashboard-company-stats")

      # Exit edit mode
      view |> element("#done-layout") |> render_click()
      assert has_element?(view, "#edit-layout")
    end

    test "reorders widgets via move-up and move-down", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      view |> element("#edit-layout") |> render_click()

      # Move second widget (users) up
      view |> element("#move-up-base-dashboard-user-stats") |> render_click()

      # Move it back down
      view |> element("#move-down-base-dashboard-user-stats") |> render_click()

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
    end

    test "drag hook order applies and persists as a layout", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert widget_order(view) == [
               "base-dashboard-company-stats",
               "base-dashboard-user-stats"
             ]

      # What the DashboardSort hook pushes after a drop: the DOM order.
      render_click(view, "reorder-widgets", %{
        "ids" => ["base-dashboard-user-stats", "base-dashboard-company-stats"]
      })

      assert widget_order(view) == [
               "base-dashboard-user-stats",
               "base-dashboard-company-stats"
             ]

      assert Settings.get("ui.dashboard.layout", Settings.Scope.user(91, 73, 41)) == [
               "base-dashboard-user-stats",
               "base-dashboard-company-stats"
             ]
    end

    test "a drag order that is not a permutation of the widgets changes nothing", %{
      conn: conn
    } do
      # A fresh user: the suite is async: false and shares one sandbox, so an
      # earlier persistence test must not count as this user's baseline. The
      # login path validates the user row, so the fixture must exist too.
      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace Hopper",
        email: "grace@example.com"
      })

      conn = log_in_as(conn, session_user(%{"user_id" => 92}))

      {:ok, view, _html} = conn |> live(~p"/dashboard")

      # Stale patch: the ids no longer match the live widgets.
      render_click(view, "reorder-widgets", %{
        "ids" => ["base-dashboard-user-stats", "base-dashboard-recent-audit"]
      })

      # Dropped id.
      render_click(view, "reorder-widgets", %{"ids" => ["base-dashboard-user-stats"]})

      # Duplicated id.
      render_click(view, "reorder-widgets", %{
        "ids" => [
          "base-dashboard-company-stats",
          "base-dashboard-company-stats"
        ]
      })

      # Forged id.
      render_click(view, "reorder-widgets", %{"ids" => ["forged-widget"]})

      assert widget_order(view) == [
               "base-dashboard-company-stats",
               "base-dashboard-user-stats"
             ]

      refute Settings.overridden?("ui.dashboard.layout", Settings.Scope.user(92, 73, 41))
    end

    test "drag handles appear only while editing", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      refute has_element?(view, "#drag-base-dashboard-company-stats")

      view |> element("#edit-layout") |> render_click()

      assert has_element?(view, "#drag-base-dashboard-company-stats")
      assert has_element?(view, "#drag-base-dashboard-company-stats")
      assert has_element?(view, "#dashboard-widgets[data-sort-enabled='true']")
    end

    test "the layout setting answers with its declared empty default when nothing is stored",
         %{conn: _conn} do
      # The trap this whole group guards. `core/user` declares
      # `ui.dashboard.layout` with `default: []`, so an unset layout reads back
      # as an empty list, not as nil. Pin it: if this ever answers nil, the
      # reader below can be simplified, and if it keeps answering [] the reader
      # must not treat that as a user choice.
      assert Settings.get("ui.dashboard.layout", Settings.Scope.user(91, 73, 41)) == []
    end

    test "an account that never customised its dashboard sees the whole catalogue",
         %{conn: conn} do
      # `ui.dashboard.layout` is declared with `default: []`, so reading the
      # value cannot tell "never customised" apart from "emptied on purpose".
      # This account has stored nothing.
      refute Settings.overridden?("ui.dashboard.layout", Settings.Scope.user(91, 73, 41))

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      refute has_element?(view, "#dashboard-widgets-empty")
    end

    test "a stored empty layout stays empty rather than reverting to the catalogue",
         %{conn: conn} do
      Settings.put("ui.dashboard.layout", [], Settings.Scope.user(91, 73, 41))

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#dashboard-widgets-empty")
      refute has_element?(view, "#stat-companies")
      refute has_element?(view, "#stat-users")
    end

    test "displays empty state when all widgets are removed", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      view |> element("#edit-layout") |> render_click()
      view |> element("#remove-base-dashboard-company-stats") |> render_click()
      view |> element("#remove-base-dashboard-user-stats") |> render_click()

      refute has_element?(view, "#dashboard-widgets")
      assert has_element?(view, "#dashboard-widgets-empty")
      assert render(view) =~ "No widgets configured."
    end
  end

  describe "auto-refresh" do
    test "handles :refresh_widgets message and updates live audit entries", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!(["admin.audit.log.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-recent-audit")
      assert render(view) =~ "No recent activity."

      {:ok, mutation} =
        Audit.record_mutation(scope, %{
          actor_type: "user",
          actor_id: 91,
          auditable_type: "User",
          auditable_id: "91",
          event: "updated",
          source: "listener",
          occurred_at: NaiveDateTime.utc_now()
        })

      send(view.pid, :refresh_widgets)

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-recent-audit")
      refute render(view) =~ "No recent activity."
      assert has_element?(view, "#audit-entry-#{mutation.id}")
      assert render(view) =~ "updated"
      assert render(view) =~ "User"
    end

    test "refresh recomputes the session count", %{conn: conn} do
      grant_capabilities!(["admin.system.session.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-sessions", "1")

      Session.put_session("dash-refreshed", "opaque", %{
        user_id: 91,
        ip_address: "127.0.0.3",
        user_agent: "Bilimbi test",
        last_activity: 300
      })

      send(view.pid, :refresh_widgets)

      assert has_element?(view, "#stat-sessions", "2")
    end
  end

  # The drag hook pushes DOM order, so order is what the test must observe:
  # the position of each widget wrapper's id within the rendered grid.
  defp widget_order(view) do
    html = render(view)

    ~r{id="widget-([^"]+)"}
    |> Regex.scan(html)
    |> Enum.map(fn [_match, id] -> id end)
  end
end
