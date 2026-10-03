defmodule Bilimbi.Base.Dashboard.Web.IndexLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.UI.DiscoveredPanels
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Bilimbi local development"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    {:ok, scope} = Tenancy.scope(41)
    {:ok, scope: scope}
  end

  test "shows the workspace identity and real counts", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    refute has_element?(view, "#app-tenant")
    assert has_element?(view, "#app-user-panel", "Bilimbi local development")
    assert has_element?(view, "#app-user-panel #app-user-platform-operator", "Platform-operator")
    refute has_element?(view, "#app-scope-warning")

    assert has_element?(view, "#stat-companies", "1")
    assert has_element?(view, "#stat-users", "1")
    assert has_element?(view, "#stat-companies-item-2")
    refute has_element?(view, "#stat-companies-item-3")
    assert has_element?(view, "#stat-users-item-2")
    refute has_element?(view, "#stat-users-item-3")

    assert has_element?(
             view,
             "#dashboard-current-company[data-company-id='73']"
           )

    assert has_element?(view, "#dashboard-company-name", "Bilimbi Industries")
  end

  test "counts all accounts but renders a bounded workspace preview", %{conn: conn} do
    for id <- 92..98 do
      UserFixtures.insert_user!(%{id: id, company_id: 73, email: "preview#{id}@example.com"})
    end

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")
    assert has_element?(view, "#stat-users", "8")
    assert has_element?(view, "#dashboard-user-95")
    refute has_element?(view, "#dashboard-user-96")
  end

  test "lists users affiliated with the tenant's companies", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#dashboard-users")
    assert has_element?(view, "#dashboard-user-91 td", "Ada Lovelace")
  end

  test "shell pins load with the page and stay across a refresh", %{conn: conn} do
    {:ok, :pinned, _} = User.toggle_user_pin(91, %{"label" => "Companies", "url" => "/companies"})
    conn = log_in_as(conn)
    owner = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      Bilimbi.Base.Repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, owner ->
        if metadata.source == "user_pins" and match?({:ok, %{command: :select}}, metadata.result) do
          send(owner, :pin_read)
        end
      end,
      owner
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    assert pin_reads() == 2
    assert has_element?(view, ~s(#app-shell[data-pins*="/companies"]))

    view |> element("#customize-layout") |> render_click()
    assert pin_reads() == 0
    assert has_element?(view, ~s(#app-shell[data-pins*="/companies"]))

    render_hook(view, "shell:preference", %{kind: "theme", value: "dark"})
    assert pin_reads() == 0
    assert has_element?(view, ~s(#app-shell[data-pins*="/companies"]))
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
    assert has_element?(view, ~s(#app-shell[data-pins="[]"]))
    assert has_element?(view, "#app-sidebar-drag")
    refute has_element?(view, "#nav-dashboard")
    # The workspace needs no capability, so even an account with no role has
    # that one destination; the "no destinations" sentence is for none at all.
    assert has_element?(view, "#nav-workspace[href='/workspace']")
    refute has_element?(view, "#app-nav-empty")
    refute has_element?(view, "#nav-admin-company")
    refute has_element?(view, "#nav-admin-user")
    refute has_element?(view, "#dashboard-company-open")
    assert has_element?(view, "#app-user-name", "Ada Lovelace")
    assert has_element?(view, "#app-user-logout")
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
    assert has_element?(view, "#nav-tile-admin-company[data-nav-tile='/companies']")
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

  describe "module-declared panels" do
    test "every installed entry names an installed panel gated by the same capability" do
      entries = Dashboard.entries()

      assert Enum.map(entries, & &1.id) == [
               "base-dashboard-company-stats",
               "current-company",
               "base-dashboard-user-stats",
               "recent-users",
               "base-dashboard-recent-audit",
               "base-dashboard-session-stats",
               "base-perf-health"
             ]

      for entry <- entries do
        assert {:ok, panel} = DiscoveredPanels.resolve(entry.embed)
        assert panel.capability == entry.capability
        assert Code.ensure_loaded?(panel.live_component)
      end
    end

    test "the page is served by the dashboard module, not the host" do
      assert %{phoenix_live_view: {Bilimbi.Base.Dashboard.Web.IndexLive, _, _, _}} =
               Phoenix.Router.route_info(BilimbiWeb.Router, "GET", "/dashboard", "localhost")
    end

    test "an entry whose panel is not installed says so instead of rendering nothing",
         %{conn: conn} do
      with_dashboard_catalogue!([
        Dashboard.Widget.new!(%{id: "orphan", label: "Orphan", embed: "dashboard.orphan"})
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(
               view,
               "#widget-orphan #dashboard-panel-orphan",
               "This panel is provided by a module that is not installed (dashboard.orphan)."
             )
    end

    test "shows the shell notification bell in the top bar", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#app-topbar #app-shell-notifications")
    end

    test "section controls replace the open links while customizing", %{conn: conn} do
      grant_capabilities!(["admin.company.view", "admin.user.list"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#dashboard-company-open")
      assert has_element?(view, "#dashboard-users-open[href='/users']")
      refute has_element?(view, "#move-section-up-recent-users")

      view |> element("#customize-layout") |> render_click()

      refute has_element?(view, "#dashboard-company-open")
      refute has_element?(view, "#dashboard-users-open")
      view |> element("#move-section-up-recent-users") |> render_click()
      assert section_order(view) == ["recent-users", "current-company"]

      assert Settings.get("ui.dashboard.sections", Settings.Scope.user(91, 73, 41)) == [
               "recent-users",
               "current-company"
             ]
    end
  end

  describe "widget capability isolation" do
    test "unprivileged user sees only ungated widgets and cannot see gated widgets in available list",
         %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      refute has_element?(view, "#stat-recent-audit")

      # Enter edit mode
      view |> element("#customize-layout") |> render_click()

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

    test "a grid emptied only by capability says so and names the capabilities",
         %{conn: conn} do
      # Every contributed widget is gated, and this account holds none of the
      # capabilities. Pointing at Customize would be a dead end: there is
      # nothing this account could add.
      with_dashboard_catalogue!(gated_catalogue())
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      refute has_element?(view, "#dashboard-widgets-empty")
      refute has_element?(view, "#dashboard-widgets-none")

      assert has_element?(
               view,
               "#dashboard-widgets-withheld",
               "You do not have permission to see the dashboard widgets"
             )

      assert has_element?(
               view,
               "#dashboard-widgets-withheld",
               "Ask an operator to review your role."
             )

      for capability <- ["admin.audit.log.list", "admin.system.session.list"] do
        assert has_element?(view, "#dashboard-widgets-withheld", capability)
      end

      {rest, [last]} =
        gated_catalogue()
        |> Enum.map(& &1.capability)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.split(-1)

      assert has_element?(
               view,
               "#dashboard-widgets-withheld",
               "You do not have permission to see the dashboard widgets; each widget needs its " <>
                 "own permission, and these widgets use #{Enum.join(rest, ", ")} and #{last}."
             )

      refute has_element?(view, "#dashboard-widgets-withheld", "one of")
    end

    test "a grid withheld by one capability names it alone", %{conn: conn} do
      with_dashboard_catalogue!(
        Enum.filter(gated_catalogue(), &(&1.capability == "admin.audit.log.list"))
      )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(
               view,
               "#dashboard-widgets-withheld",
               "You do not have permission to see the dashboard widgets, each of which " <>
                 "needs admin.audit.log.list."
             )

      refute has_element?(view, "#dashboard-widgets-withheld", "its own permission")
      refute has_element?(view, "#dashboard-widgets-withheld", "one of")
    end

    test "a catalogue nothing contributes to says so, not that it is out of reach",
         %{conn: conn} do
      with_dashboard_catalogue!([])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      refute has_element?(view, "#dashboard-widgets-empty")
      refute has_element?(view, "#dashboard-widgets-withheld")

      assert has_element?(
               view,
               "#dashboard-widgets-none",
               "No installed module contributes dashboard widgets."
             )
    end

    test "the first HTML does not report deferred widgets as empty", %{conn: conn, scope: scope} do
      grant_capabilities!([
        "admin.audit.log.list",
        "admin.system.session.list",
        "admin.system.perf.view"
      ])

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

      conn = conn |> log_in_as() |> get(~p"/dashboard")
      html = html_response(conn, 200)

      assert html =~ ~s(id="stat-recent-audit-pending")
      refute html =~ "No recent activity."
      refute html =~ "audit-entry-#{mutation.id}"
      assert cell_text(html, "stat-sessions-item-0") == "Open—"
      assert cell_text(html, "stat-performance-item-0") == "Health—"
      refute cell_text(html, "stat-performance-item-0") =~ "Unknown"

      {:ok, view, _html} = live(conn)

      assert has_element?(view, "#audit-entry-#{mutation.id}")
      refute has_element?(view, "#stat-recent-audit-pending")
      refute render(view) =~ "No recent activity."
      assert has_element?(view, "#stat-sessions", "1")
      refute render(view) =~ "Unknown"
    end

    test "shows gated widgets when corresponding capabilities are granted", %{conn: conn} do
      grant_capabilities!(["admin.audit.log.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      assert has_element?(view, "#stat-companies")
      assert has_element?(view, "#stat-users")
      assert has_element?(view, "#stat-recent-audit")
      assert has_element?(view, "#stat-recent-audit-empty", "No recent activity.")

      assert has_element?(
               view,
               "#stat-recent-audit-open[href='/audit/mutations'][aria-label='Open audit log']"
             )

      view |> element("#customize-layout") |> render_click()

      assert has_element?(view, "#stat-recent-audit")
      refute has_element?(view, "#stat-recent-audit-open")
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
      refute has_element?(view, "#stat-recent-audit-empty")
      assert has_element?(view, "#audit-entry-#{mutation.id}")
      assert render(view) =~ "created"
      assert render(view) =~ "Company"
    end

    test "session widget stays hidden without admin.system.session.list", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      refute has_element?(view, "#stat-sessions")

      # Not offered for adding either.
      view |> element("#customize-layout") |> render_click()
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
    test "adding hidden activity loads entries immediately, including after a hidden refresh", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!(["admin.audit.log.list"])
      Settings.put("ui.dashboard.layout", [], Settings.Scope.user(91, 73, 41))

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
      refute has_element?(view, "#stat-recent-audit")
      view |> element("#customize-layout") |> render_click()
      view |> element("#add-widget-base-dashboard-recent-audit") |> render_click()
      assert has_element?(view, "#audit-entry-#{mutation.id}")

      view |> element("#remove-base-dashboard-recent-audit") |> render_click()
      send(view.pid, :refresh_widgets)
      refute has_element?(view, "#stat-recent-audit")
      view |> element("#add-widget-base-dashboard-recent-audit") |> render_click()
      assert has_element?(view, "#audit-entry-#{mutation.id}")
    end

    test "removes and re-adds widgets, persisting layout to settings", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      # Enter edit mode
      view |> element("#customize-layout") |> render_click()
      assert has_element?(view, "#close-customize")

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
      view |> element("#close-customize") |> render_click()
      assert has_element?(view, "#customize-layout")
    end

    test "reorders widgets via move-up and move-down", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      view |> element("#customize-layout") |> render_click()

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

      view |> element("#customize-layout") |> render_click()

      assert has_element?(view, "#drag-base-dashboard-company-stats")
      assert has_element?(view, "#drag-base-dashboard-company-stats")
      assert has_element?(view, "#dashboard-widgets[data-sort-enabled='true']")
    end

    test "forged section ids leave visible and available sections unchanged", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      view |> element("#customize-layout") |> render_click()

      render_click(view, "remove-section", %{"id" => "forged-section"})

      assert section_order(view) == ["current-company", "recent-users"]
      refute has_element?(view, "#add-section-current-company")
      refute has_element?(view, "#add-section-recent-users")
      refute Settings.overridden?("ui.dashboard.sections", Settings.Scope.user(91, 73, 41))

      view |> element("#remove-section-recent-users") |> render_click()

      assert section_order(view) == ["current-company"]
      assert has_element?(view, "#add-section-recent-users")

      assert Settings.get("ui.dashboard.sections", Settings.Scope.user(91, 73, 41)) == [
               "current-company"
             ]

      render_click(view, "add-section", %{"id" => "forged-section"})

      assert section_order(view) == ["current-company"]
      assert has_element?(view, "#add-section-recent-users")

      assert Settings.get("ui.dashboard.sections", Settings.Scope.user(91, 73, 41)) == [
               "current-company"
             ]
    end

    test "section choices persist across remounts", %{conn: conn} do
      conn = log_in_as(conn)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("#customize-layout") |> render_click()
      view |> element("#remove-section-current-company") |> render_click()

      refute has_element?(view, "#dashboard-current-company")
      assert section_order(view) == ["recent-users"]

      assert Settings.get("ui.dashboard.sections", Settings.Scope.user(91, 73, 41)) == [
               "recent-users"
             ]

      {:ok, remounted, _html} = live(conn, ~p"/dashboard")

      refute has_element?(remounted, "#dashboard-current-company")
      assert section_order(remounted) == ["recent-users"]
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

      view |> element("#customize-layout") |> render_click()
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
      assert has_element?(view, "#stat-recent-audit-empty", "No recent activity.")

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
      refute has_element?(view, "#stat-recent-audit-empty")
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

  defp pin_reads(count \\ 0) do
    receive do
      :pin_read -> pin_reads(count + 1)
    after
      0 -> count
    end
  end

  defp cell_text(html, id) do
    [_, inner] = Regex.run(~r/id="#{id}"[^>]*>(.*?)<\/div>/s, html)
    inner |> String.replace(~r/<[^>]+>/, "") |> String.replace(~r/\s+/, "")
  end

  # The drag hook pushes DOM order, so order is what the test must observe:
  # the position of each widget wrapper's id within the rendered grid.
  defp widget_order(view) do
    html = render(view)

    ~r{id="widget-([^"]+)"}
    |> Regex.scan(html)
    |> Enum.map(fn [_match, id] -> id end)
  end

  defp section_order(view) do
    html = render(view)

    ~r{id="dashboard-(current-company|recent-users)"}
    |> Regex.scan(html)
    |> Enum.map(fn [_match, id] -> id end)
  end

  defp gated_catalogue do
    Enum.filter(Dashboard.widgets(), &(&1.capability != nil))
  end

  # The installed snapshot with only this dashboard catalogue, restored on exit.
  defp with_dashboard_catalogue!(catalogue) do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    ContributionRegistry.put_snapshot_for_test!(
      put_in(installed, [:consumers, :dashboard], catalogue)
    )
  end
end
