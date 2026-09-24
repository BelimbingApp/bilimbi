defmodule BilimbiWeb.AuditLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

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

    test "shows impersonation attribution only on impersonated mutations", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")

      {:ok, impersonated} =
        Audit.record_mutation(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 92,
          actor_role: "admin",
          impersonator_id: 91,
          auditable_type: "Bilimbi.Core.Company",
          auditable_id: "73",
          event: "updated",
          occurred_at: ~N[2026-08-18 10:01:00]
        })

      {:ok, ordinary} =
        Audit.record_mutation(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          actor_role: "owner",
          auditable_type: "Bilimbi.Core.Company",
          auditable_id: "73",
          event: "updated",
          occurred_at: ~N[2026-08-18 10:00:00]
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

      assert has_element?(
               view,
               "#mutations-#{impersonated.id}",
               "admin · impersonated by User #91"
             )

      refute has_element?(view, "#mutations-#{ordinary.id}", "impersonated by")
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
      view |> form("#mutations-filters", filters: %{"event" => "deleted"}) |> render_change()
      assert has_element?(view, "#mutations-table", "Headquarters")
      refute has_element?(view, "#mutations-table", "Ada Lovelace")

      # Search
      view
      |> form("#mutations-filters", filters: %{"search" => "Ada Lovelace", "event" => ""})
      |> render_change()

      assert has_element?(view, "#mutations-table", "Ada Lovelace")
      refute has_element?(view, "#mutations-table", "Headquarters")

      # Search no results
      view
      |> form("#mutations-filters", filters: %{"search" => "nonexistent-item-query"})
      |> render_change()

      assert has_element?(
               view,
               "#mutations-table-empty",
               "No mutation logs match the current filters."
             )
    end

    test "keeps the result count but omits navigation for a single page", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")
      record_mutations!(scope, 1)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")
      total = captured_total(scope)
      assert total in 1..25, "the log must fit one page for this proof"

      assert has_element?(
               view,
               "#mutations-pagination-summary",
               "Showing 1 to #{total} of #{total} results"
             )

      assert has_element?(view, "#mutations-pagination-page-size")
      refute has_element?(view, "#mutations-pagination-previous")
      refute has_element?(view, "#mutations-pagination-next")
      refute has_element?(view, "#mutations-pagination-page-1")
      refute render(view) =~ "Page 1 of 1"
    end

    test "paginates with numbered pages and keeps rows per page in URL state", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")
      record_mutations!(scope, 26)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")
      total = captured_total(scope)
      assert total in 26..50, "one page of 50 must hold every row for this proof"

      assert has_element?(
               view,
               "#mutations-pagination-summary",
               "Showing 1 to 25 of #{total} results"
             )

      assert has_element?(view, "#mutations-pagination-previous[disabled]")
      assert has_element?(view, "#mutations-pagination-page-1[aria-current='page']")
      assert has_element?(view, "#mutations-pagination-page-2")
      assert has_element?(view, "#mutations-pagination-next")
      assert has_element?(view, "#mutations-table", "Widget 26")
      refute has_element?(view, "#mutations-table", "Widget 01")

      view |> element("#mutations-pagination-next") |> render_click()

      assert %{"page" => "2", "page_size" => "25"} = patched_params(view)

      assert has_element?(
               view,
               "#mutations-pagination-summary",
               "Showing 26 to #{total} of #{total} results"
             )

      assert has_element?(view, "#mutations-pagination-page-2[aria-current='page']")
      assert has_element?(view, "#mutations-pagination-next[disabled]")
      assert has_element?(view, "#mutations-table", "Widget 01")

      view
      |> form("#mutations-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
      |> render_change()

      assert %{"page" => "1", "page_size" => "50"} = patched_params(view)

      assert has_element?(
               view,
               "#mutations-pagination-summary",
               "Showing 1 to #{total} of #{total} results"
             )

      refute has_element?(view, "#mutations-pagination-next")

      {:ok, reloaded, _html} = conn |> log_in_as() |> live(~p"/audit/mutations?page_size=50")
      # A second sign-in is captured too, so the reloaded count is read afresh.
      reloaded_total = captured_total(scope)
      assert reloaded_total in 26..50

      assert has_element?(
               reloaded,
               "#mutations-pagination-summary",
               "Showing 1 to #{reloaded_total} of #{reloaded_total} results"
             )

      assert has_element?(
               reloaded,
               "#mutations-pagination-page-size option[value='50'][selected]"
             )
    end

    test "changing rows per page keeps the active filters", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")
      record_mutations!(scope, 3)

      {:ok, _deleted} =
        Audit.record_mutation(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          auditable_type: "Bilimbi.Core.Address",
          auditable_id: "10",
          subject_name: "Headquarters",
          event: "deleted",
          occurred_at: ~N[2026-08-19 09:30:00]
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/mutations")

      view
      |> form("#mutations-filters", filters: %{"search" => "Headquarters", "event" => "deleted"})
      |> render_change()

      assert %{"search" => "Headquarters", "event" => "deleted"} = patched_params(view)
      assert has_element?(view, "#mutations-pagination-summary", "Showing 1 to 1 of 1 results")

      view
      |> form("#mutations-pagination-page-size-form", %{"filters" => %{"perPage" => "100"}})
      |> render_change()

      assert %{"search" => "Headquarters", "event" => "deleted", "page_size" => "100"} =
               patched_params(view)

      assert has_element?(view, "#mutations-pagination-summary", "Showing 1 to 1 of 1 results")
      assert has_element?(view, "#mutations-table", "Headquarters")
      refute has_element?(view, "#mutations-table", "Widget 01")

      {:ok, reloaded, _html} =
        conn
        |> log_in_as()
        |> live(~p"/audit/mutations?search=Headquarters&event=deleted&page_size=100")

      assert has_element?(reloaded, "#mutations-search[value='Headquarters']")
      assert has_element?(reloaded, "#mutations-event option[value='deleted'][selected]")

      assert has_element?(
               reloaded,
               "#mutations-pagination-page-size option[value='100'][selected]"
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
    test "cannot toggle retention without admin.audit.log.manage", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.audit.log.list")

      {:ok, action} =
        Audit.record_action(
          scope,
          %{
            company_id: 73,
            actor_type: "user",
            actor_id: 91,
            event: "http.request",
            occurred_at: ~N[2026-08-18 10:15:00],
            is_retained: false
          }
        )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions?diagnostics=show")

      refute has_element?(view, "button#action-retain-#{action.id}")

      render_hook(view, "toggle_retain", %{"id" => to_string(action.id)})
      assert render(view) =~ "You do not have permission to manage audit logs."
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/audit/actions")
    end

    test "redirects away without admin.audit.log.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/audit/actions")
    end

    test "renders actions, toggles retention, and marks nav active", %{conn: conn, scope: scope} do
      grant_capabilities!(["admin.audit.log.list", "admin.audit.log.manage"])

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

      # The retain toggle carries Belimbing's bookmark pair through the icon
      # registry: outline while the row is not kept, solid once it is.
      assert has_element?(view, "#action-retain-#{action.id} .hero-bookmark")
      refute has_element?(view, "#action-retain-#{action.id} .hero-bookmark-solid")

      # Toggle retain
      view |> element("#action-retain-#{action.id}") |> render_click()
      assert has_element?(view, "#action-retain-#{action.id}[title='Remove retention']")
      assert has_element?(view, "#action-retain-#{action.id} .hero-bookmark-solid")

      # Toggle back
      view |> element("#action-retain-#{action.id}") |> render_click()
      assert has_element?(view, "#action-retain-#{action.id}[title='Retain this entry']")
      assert has_element?(view, "#action-retain-#{action.id} .hero-bookmark")
      refute has_element?(view, "#action-retain-#{action.id} .hero-bookmark-solid")
    end

    test "shows impersonation attribution only on impersonated actions", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")

      {:ok, impersonated} =
        Audit.record_action(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 92,
          actor_role: "admin",
          impersonator_id: 91,
          event: "employee.updated",
          occurred_at: ~N[2026-08-18 10:16:00]
        })

      {:ok, ordinary} =
        Audit.record_action(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          actor_role: "owner",
          event: "employee.updated",
          occurred_at: ~N[2026-08-18 10:15:00]
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      assert has_element?(
               view,
               "#actions-#{impersonated.id}",
               "admin · impersonated by User #91"
             )

      refute has_element?(view, "#actions-#{ordinary.id}", "impersonated by")
    end

    test "keeps the result count but omits navigation for a single page", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")
      record_actions!(scope, 1)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 1 of 1 results")
      assert has_element?(view, "#actions-pagination-page-size")
      refute has_element?(view, "#actions-pagination-previous")
      refute has_element?(view, "#actions-pagination-next")
      refute has_element?(view, "#actions-pagination-page-1")
      refute render(view) =~ "Page 1 of 1"
    end

    test "paginates with numbered pages and keeps rows per page in URL state", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")
      record_actions!(scope, 26)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 25 of 26 results")
      assert has_element?(view, "#actions-pagination-previous[disabled]")
      assert has_element?(view, "#actions-pagination-page-1[aria-current='page']")
      assert has_element?(view, "#actions-pagination-page-2")
      assert has_element?(view, "#actions-pagination-next")
      assert has_element?(view, "#actions-table", "trace-26")
      refute has_element?(view, "#actions-table", "trace-01")

      view |> element("#actions-pagination-page-2") |> render_click()

      assert %{"page" => "2", "page_size" => "25"} = patched_params(view)
      assert has_element?(view, "#actions-pagination-summary", "Showing 26 to 26 of 26 results")
      assert has_element?(view, "#actions-pagination-page-2[aria-current='page']")
      assert has_element?(view, "#actions-pagination-next[disabled]")
      assert has_element?(view, "#actions-table", "trace-01")

      view
      |> form("#actions-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
      |> render_change()

      assert %{"page" => "1", "page_size" => "50"} = patched_params(view)
      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 26 of 26 results")
      refute has_element?(view, "#actions-pagination-next")

      {:ok, reloaded, _html} = conn |> log_in_as() |> live(~p"/audit/actions?page_size=50")

      assert has_element?(
               reloaded,
               "#actions-pagination-summary",
               "Showing 1 to 26 of 26 results"
             )

      assert has_element?(reloaded, "#actions-pagination-page-size option[value='50'][selected]")
    end

    test "changing rows per page keeps the active filters and diagnostics", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")
      record_actions!(scope, 2)

      {:ok, _livewire} =
        Audit.record_action(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          event: "http.request",
          url: "https://example.test/livewire/update",
          payload: %{"method" => "POST", "status" => 200},
          occurred_at: ~N[2026-08-19 09:00:00],
          trace_id: "trc-livewire"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      view
      |> form("#actions-filters", filters: %{"search" => "livewire", "diagnostics" => "show"})
      |> render_change()

      assert %{"search" => "livewire", "diagnostics" => "show"} = patched_params(view)
      assert has_element?(view, "#actions-table", "trc-livewire")
      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 1 of 1 results")

      view
      |> form("#actions-pagination-page-size-form", %{"filters" => %{"perPage" => "100"}})
      |> render_change()

      assert %{"search" => "livewire", "diagnostics" => "show", "page_size" => "100"} =
               patched_params(view)

      assert has_element?(view, "#actions-table", "trc-livewire")
      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 1 of 1 results")

      {:ok, reloaded, _html} =
        conn
        |> log_in_as()
        |> live(~p"/audit/actions?search=livewire&diagnostics=show&page_size=100")

      assert has_element?(reloaded, "#actions-search[value='livewire']")
      assert has_element?(reloaded, "#actions-diagnostics option[value='show'][selected]")
      assert has_element?(reloaded, "#actions-pagination-page-size option[value='100'][selected]")
    end

    test "a console command shows what was typed and what became of it", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.audit.log.list")

      {:ok, _executed} =
        Audit.record_action(scope, %{
          actor_type: "user",
          actor_id: 91,
          event: "database_query.executed",
          payload: %{
            "sql" => "SELECT id FROM users",
            "name" => "All ids",
            "result" => "succeeded",
            "row_count" => 3
          },
          occurred_at: ~N[2026-08-18 09:00:00]
        })

      {:ok, _refused} =
        Audit.record_action(scope, %{
          actor_type: "user",
          actor_id: 91,
          event: "database_query.refused",
          payload: %{
            "sql" => "SELECT 1; DELETE FROM users",
            "result" => "refused",
            "guard" => "keyword",
            "message" => "Write or DDL statements are not permitted in queries."
          },
          occurred_at: ~N[2026-08-18 09:01:00]
        })

      {:ok, _failed} =
        Audit.record_action(scope, %{
          actor_type: "user",
          actor_id: 91,
          event: "database_query.failed",
          payload: %{
            "sql" => "SELECT * FROM nowhere",
            "result" => "failed",
            "message" => "relation \"nowhere\" does not exist"
          },
          occurred_at: ~N[2026-08-18 09:02:00]
        })

      {:ok, _unrelated} =
        Audit.record_action(scope, %{
          actor_type: "guest",
          actor_id: 0,
          event: "auth.login.failed",
          payload: %{"email" => "hacker@example.test"},
          occurred_at: ~N[2026-08-18 09:03:00]
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/audit/actions")

      assert has_element?(view, "#actions-table", "All ids")
      assert has_element?(view, "#actions-table", "Succeeded · 3 rows")
      assert has_element?(view, "#actions-table", "SELECT id FROM users")
      assert has_element?(view, "#actions-table", "Refused · Keyword")
      assert has_element?(view, "#actions-table", "SELECT 1; DELETE FROM users")
      assert has_element?(view, "#actions-table", "Failed")

      # The family filter finds every console command and nothing else.
      view
      |> form("#actions-filters", filters: %{"event_family" => "database"})
      |> render_change()

      assert has_element?(view, "#actions-pagination-summary", "Showing 1 to 3 of 3 results")
      refute has_element?(view, "#actions-table", "hacker@example.test")

      # A refused command is a failure to a reader looking for trouble.
      view
      |> form("#actions-filters", filters: %{"event_family" => "", "result" => "failure"})
      |> render_change()

      assert has_element?(view, "#actions-table", "Refused · Keyword")
      assert has_element?(view, "#actions-table", "SELECT * FROM nowhere")
      refute has_element?(view, "#actions-table", "All ids")
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
      view |> form("#actions-filters", filters: %{"event_family" => "console"}) |> render_change()
      assert has_element?(view, "#actions-table", "bilimbi.migrate")
      refute has_element?(view, "#actions-table", "hacker@example.test")

      # Filter by result = failure
      view
      |> form("#actions-filters", filters: %{"event_family" => "", "result" => "failure"})
      |> render_change()

      assert has_element?(view, "#actions-table", "hacker@example.test")
      refute has_element?(view, "#actions-table", "bilimbi.migrate")

      # Filter by actor_type = guest
      view
      |> form("#actions-filters", filters: %{"actor_type" => "guest", "result" => ""})
      |> render_change()

      assert has_element?(view, "#actions-table", "Guest")

      # Search
      view
      |> form("#actions-filters", filters: %{"search" => "migrate", "actor_type" => ""})
      |> render_change()

      assert has_element?(view, "#actions-table", "bilimbi.migrate")
      refute has_element?(view, "#actions-table", "hacker@example.test")
    end
  end

  # Signing in and mounting the page are themselves captured mutations, so the
  # log holds more than the rows a test recorded. The count the module reports
  # after mount is what the summary must show.
  defp captured_total(scope) do
    Audit.list_mutations(scope, page_size: 300).total_entries
  end

  # `count` mutations, oldest first and older than anything write capture
  # records, so the newest-first default lands the highest number on page one.
  # Subjects pad to two digits so "Widget 1" cannot match "Widget 10" by prefix.
  # Returns `count` so a caller can add it to the baseline.
  defp record_mutations!(scope, count) do
    for index <- 1..count do
      number = String.pad_leading("#{index}", 2, "0")

      {:ok, _mutation} =
        Audit.record_mutation(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          auditable_type: "Bilimbi.Core.Company",
          auditable_id: number,
          subject_name: "Widget #{number}",
          event: "updated",
          occurred_at: NaiveDateTime.add(~N[2026-08-18 10:00:00], index, :minute)
        })
    end

    count
  end

  defp record_actions!(scope, count) do
    for index <- 1..count do
      number = String.pad_leading("#{index}", 2, "0")

      {:ok, _action} =
        Audit.record_action(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          event: "employee.updated",
          occurred_at: NaiveDateTime.add(~N[2026-08-18 10:00:00], index, :minute),
          trace_id: "trace-#{number}"
        })
    end

    count
  end

  defp patched_params(view) do
    assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
