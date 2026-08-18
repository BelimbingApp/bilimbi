defmodule BilimbiWeb.AuditLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures

  setup do
    UserFixtures.create_user_tables!()
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  describe "Data Mutations (/audit/mutations)" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/audit/mutations")
    end

    test "redirects away without admin.audit.log.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/audit/mutations")
    end

    test "renders data mutations and marks nav active", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")

      {:ok, _mutation} =
        Audit.record_mutation(
          scope,
          %{
            company_id: 73,
            actor_type: "user",
            actor_id: 91,
            actor_role: "owner",
            auditable_type: "Bilimbi.Core.Company",
            auditable_id: "73",
            subject_name: "Acme Corp",
            event: "updated",
            occurred_at: ~N[2026-08-18 10:00:00],
            old_values: %{"name" => "Acme Inc"},
            new_values: %{"name" => "Acme Corp"},
            trace_id: "trc123456"
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

      assert has_element?(view, "h1", "Data Mutations")
      assert has_element?(view, "#nav-admin-audit-mutation[aria-current='page']")
      assert has_element?(view, "#mutations-table", "User #91")
      assert has_element?(view, "#mutations-table", "Acme Corp")
      assert has_element?(view, "#mutations-table", "Company #73")
      assert has_element?(view, "#mutations-table", "Acme Inc")
      assert has_element?(view, "#mutations-table", "trc123456")
    end

    test "filters and searches mutations", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")

      {:ok, _created} =
        Audit.record_mutation(
          scope,
          %{
            company_id: 73,
            actor_type: "user",
            actor_id: 91,
            auditable_type: "Bilimbi.Core.User",
            auditable_id: "91",
            subject_name: "Ada Lovelace",
            event: "created",
            occurred_at: ~N[2026-08-18 09:00:00],
            new_values: %{"email" => "ada@example.test"}
          }
        )

      {:ok, _deleted} =
        Audit.record_mutation(
          scope,
          %{
            company_id: 73,
            actor_type: "agent",
            actor_id: 1,
            auditable_type: "Bilimbi.Core.Address",
            auditable_id: "10",
            subject_name: "Headquarters",
            event: "deleted",
            occurred_at: ~N[2026-08-18 09:30:00],
            old_values: %{"city" => "London"}
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

      assert has_element?(view, "#mutations-table", "Ada Lovelace")
      assert has_element?(view, "#mutations-table", "Headquarters")

      # Filter by event
      view |> form("#mutations-filters", %{"event" => "deleted"}) |> render_change()
      assert has_element?(view, "#mutations-table", "Headquarters")
      refute has_element?(view, "#mutations-table", "Ada Lovelace")

      # Search
      view
      |> form("#mutations-filters", %{"search" => "Ada Lovelace", "event" => ""})
      |> render_change()

      assert has_element?(view, "#mutations-table", "Ada Lovelace")
      refute has_element?(view, "#mutations-table", "Headquarters")

      # Search no results
      view
      |> form("#mutations-filters", %{"search" => "nonexistent-item-query"})
      |> render_change()

      assert has_element?(
               view,
               "#mutations-table-empty",
               "No mutation logs match the current filters."
             )
    end

    test "sorts mutations by column", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")

      {:ok, _} =
        Audit.record_mutation(
          scope,
          %{
            company_id: 73,
            actor_type: "user",
            actor_id: 91,
            auditable_type: "Bilimbi.Core.User",
            auditable_id: "91",
            event: "created",
            occurred_at: ~N[2026-08-18 08:00:00]
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

      view |> element("#mutations-sort-event") |> render_click()
      assert %{"sort_by" => "event", "sort_dir" => "asc"} = patched_params(view)
    end
  end

  describe "Audit Actions (/audit/actions)" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/audit/actions")
    end

    test "redirects away without admin.audit.log.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/audit/actions")
    end

    test "renders actions, toggles retention, and marks nav active", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")

      {:ok, action} =
        Audit.record_action(
          scope,
          %{
            company_id: 73,
            actor_type: "user",
            actor_id: 91,
            actor_role: "admin",
            event: "http.request",
            url: "https://example.test/admin/companies",
            payload: %{"method" => "GET", "status" => 200, "duration_ms" => 42.5},
            occurred_at: ~N[2026-08-18 10:15:00],
            is_retained: false,
            trace_id: "trc999888"
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions?diagnostics=show")

      assert has_element?(view, "h1", "Audit Actions")
      assert has_element?(view, "#nav-admin-audit-action[aria-current='page']")
      assert has_element?(view, "#actions-table", "User #91")
      assert has_element?(view, "#actions-table", "GET /admin/companies")
      assert has_element?(view, "#actions-table", "200 · 43 ms")
      assert has_element?(view, "#actions-table", "trc999888")

      # Toggle retain
      view |> element("#action-retain-#{action.id}") |> render_click()
      assert has_element?(view, "#action-retain-#{action.id}[title='Remove retention']")
      assert has_element?(view, "#action-retain-#{action.id} .hero-bookmark-solid")

      # Toggle back
      view |> element("#action-retain-#{action.id}") |> render_click()
      assert has_element?(view, "#action-retain-#{action.id}[title='Retain this entry']")
    end

    test "filters actions by family, actor_type, result, and diagnostics", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")

      {:ok, _auth_failed} =
        Audit.record_action(
          scope,
          %{
            actor_type: "guest",
            actor_id: 0,
            event: "auth.login.failed",
            payload: %{"email" => "hacker@example.test"},
            occurred_at: ~N[2026-08-18 09:00:00]
          }
        )

      {:ok, _console_cmd} =
        Audit.record_action(
          scope,
          %{
            actor_type: "console",
            actor_id: 0,
            event: "console.command",
            payload: %{"command" => "bilimbi.migrate", "exit_code" => 0},
            occurred_at: ~N[2026-08-18 09:05:00]
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      # Filter by family = console
      view |> form("#actions-filters", %{"event_family" => "console"}) |> render_change()
      assert has_element?(view, "#actions-table", "bilimbi.migrate")
      refute has_element?(view, "#actions-table", "hacker@example.test")

      # Filter by result = failure
      view
      |> form("#actions-filters", %{"event_family" => "", "result" => "failure"})
      |> render_change()

      assert has_element?(view, "#actions-table", "hacker@example.test")
      refute has_element?(view, "#actions-table", "bilimbi.migrate")

      # Filter by actor_type = guest
      view
      |> form("#actions-filters", %{"actor_type" => "guest", "result" => ""})
      |> render_change()

      assert has_element?(view, "#actions-table", "Guest")

      # Search
      view
      |> form("#actions-filters", %{"search" => "migrate", "actor_type" => ""})
      |> render_change()

      assert has_element?(view, "#actions-table", "bilimbi.migrate")
      refute has_element?(view, "#actions-table", "hacker@example.test")
    end
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
