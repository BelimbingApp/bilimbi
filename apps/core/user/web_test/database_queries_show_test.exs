defmodule BilimbiWeb.DatabaseQueriesShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_database_queries_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)

    %{scope: scope}
  end

  describe "Show LiveView (/admin/system/database-queries/:slug)" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/admin/system/database-queries/active-users")
    end

    test "read-only user can view and execute query but cannot modify or see mutation buttons", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Read Only Query",
          description: "For viewing",
          sql_query: "SELECT id, name FROM users;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(view, "#query-name-input[value='Read Only Query']")
      refute has_element?(view, "#btn-save-query")
      refute has_element?(view, "#btn-duplicate-query")
      refute has_element?(view, "#btn-delete-query")

      assert has_element?(
               view,
               "a#database-query-back[href='/admin/system/database-queries'][title='Back to database queries']",
               "Back"
             )

      refute has_element?(view, "button#database-query-back")

      # Server-side event authorization rejection
      for event <- ["save", "duplicate", "delete"] do
        render_click(view, event)
        assert has_element?(view, "#flash-error", "You are not authorized to modify queries.")
      end
    end

    test "warns, where SQL runs, that the console reads across every company", %{
      conn: conn,
      scope: scope
    } do
      # `Database.QueryExecutor` applies no tenant predicate, and only the
      # operator scope reaches this page, so the caution is true whenever it is
      # read: on a saved query and on a new one, in the warning tokens.
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Reach Query",
          sql_query: "SELECT id FROM users;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(
               view,
               "#sql-editor-card #database-query-reach-caution.bg-warning-surface",
               "every company and tenant"
             )

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      assert has_element?(view, "#database-query-reach-caution", "every company and tenant")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")
      refute has_element?(view, "#database-query-reach-caution")
    end

    test "creates a new query via _new with edit capability", %{conn: conn, scope: scope} do
      grant_capabilities!([
        "admin.system.database-table.list",
        "admin.system.database-table.edit"
      ])

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      assert page_title(view) =~ "New Query"
      assert has_element?(view, "#btn-save-query")

      # Fill in fields
      view
      |> form("#query-title-form", %{name: "All Users Query"})
      |> render_change()

      view
      |> form("#query-desc-form", %{description: "Fetches all users"})
      |> render_change()

      view
      |> form("#query-sql-form", %{sql_query: "SELECT id, name FROM users;"})
      |> render_change()

      # Save query
      view |> element("#btn-save-query") |> render_click()
      assert_redirect(view, ~p"/admin/system/database-queries/all-users-query")

      # Verify query exists in DB
      assert {:ok, created} = User.get_database_query(as(scope, 91), "all-users-query")
      assert created.name == "All Users Query"
      assert created.sql_query == "SELECT id, name FROM users;"
    end

    test "executes query, detects named parameters, records the command, and displays results",
         %{
           conn: conn,
           scope: scope
         } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Find User By Name",
          description: "Search user by name parameter",
          sql_query: "SELECT id, name FROM users WHERE name = :user_name;"
        })

      {:ok, view, _html} =
        conn
        |> put_req_header("user-agent", "ConsoleTest/1.0 (needle-agent)")
        |> log_in_as()
        |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(view, "#query-name-input[value='Find User By Name']")
      assert has_element?(view, "#param-input-user_name")

      # The page ran the saved query on each of its two mounts (the
      # disconnected render, then the socket): both are commands, recorded
      # before the reader has clicked anything.
      mounted = console_actions(scope)
      assert length(mounted) == 2
      assert Enum.all?(mounted, &(&1.event == "database_query.executed"))

      # Set parameter value
      view
      |> form("#query-params-form", %{"user_name" => "Ada Lovelace"})
      |> render_change()

      # Run query
      view |> element("#btn-run-query") |> render_click()

      assert has_element?(view, "#query-results-table", "Ada Lovelace")
      assert has_element?(view, "#query-results-summary", "1 total rows")

      # One record per command, naming who ran it, from where, what they
      # typed, and what it did — and never the row it returned.
      assert [run] = console_actions(scope) -- mounted
      assert run.event == "database_query.executed"
      assert run.actor_type == "user"
      assert run.actor_id == 91
      assert run.company_id == 73
      assert run.tenant_id == 41
      assert run.impersonator_id == nil
      assert run.ip_address == %Postgrex.INET{address: {127, 0, 0, 1}}
      assert run.user_agent == "ConsoleTest/1.0 (needle-agent)"
      assert run.url =~ ~p"/admin/system/database-queries/#{query.slug}"
      assert run.is_retained == false

      assert run.payload == %{
               "sql" => "SELECT id, name FROM users WHERE name = :user_name;",
               "name" => "Find User By Name",
               "result" => "succeeded",
               "row_count" => 1
             }

      refute inspect(run.payload) =~ "Ada Lovelace"
    end

    test "a command refused by the first-word check is recorded as refused, with the actor", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      view
      |> form("#query-sql-form", %{sql_query: "DELETE FROM users"})
      |> render_change()

      view |> element("#btn-run-query") |> render_click()

      assert has_element?(
               view,
               "#query-execution-error",
               "Only SELECT or WITH queries are permitted."
             )

      assert [refused] = console_actions(scope)
      assert refused.event == "database_query.refused"
      assert refused.actor_id == 91
      assert refused.ip_address == %Postgrex.INET{address: {127, 0, 0, 1}}
      assert refused.url =~ ~p"/admin/system/database-queries/_new"

      assert refused.payload == %{
               "sql" => "DELETE FROM users",
               "name" => "Untitled Query",
               "result" => "refused",
               "guard" => "statement",
               "message" => "Only SELECT or WITH queries are permitted."
             }
    end

    test "a command refused by the keyword block is recorded as refused by that guard", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      view
      |> form("#query-sql-form", %{sql_query: "SELECT 1; DELETE FROM users"})
      |> render_change()

      view |> element("#btn-run-query") |> render_click()

      assert has_element?(
               view,
               "#query-execution-error",
               "Write or DDL statements are not permitted in queries."
             )

      assert [refused] = console_actions(scope)
      assert refused.event == "database_query.refused"
      assert refused.actor_id == 91
      assert refused.payload["guard"] == "keyword"
      assert refused.payload["sql"] == "SELECT 1; DELETE FROM users"
    end

    test "a write PostgreSQL refuses is recorded as refused by the read-only transaction", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")
      Bilimbi.Base.Repo.query!("CREATE SEQUENCE __blb_console_page_probe START 1")

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      # Passes both text guards; only the database can refuse it.
      view
      |> form("#query-sql-form", %{sql_query: "SELECT setval('__blb_console_page_probe', 42)"})
      |> render_change()

      view |> element("#btn-run-query") |> render_click()
      assert has_element?(view, "#query-execution-error", "read-only transaction")

      assert [refused] = console_actions(scope)
      assert refused.event == "database_query.refused"
      assert refused.actor_id == 91
      assert refused.payload["guard"] == "read_only_transaction"
      assert refused.payload["message"] =~ "read-only transaction"
      assert refused.payload["sql"] == "SELECT setval('__blb_console_page_probe', 42)"
    end

    test "a failing command is recorded as failed, with the database's message and the actor",
         %{
           conn: conn,
           scope: scope
         } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      view
      |> form("#query-sql-form", %{sql_query: "SELECT * FROM __blb_absent_console_table"})
      |> render_change()

      view |> element("#btn-run-query") |> render_click()
      assert has_element?(view, "#query-execution-error", "does not exist")

      assert [failed] = console_actions(scope)
      assert failed.event == "database_query.failed"
      assert failed.actor_type == "user"
      assert failed.actor_id == 91
      assert failed.ip_address == %Postgrex.INET{address: {127, 0, 0, 1}}
      assert failed.payload["result"] == "failed"
      assert failed.payload["message"] =~ "does not exist"
      assert failed.payload["sql"] == "SELECT * FROM __blb_absent_console_table"
    end

    test "paging and sorting a result re-run the command, and each run is recorded", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Users",
          sql_query: "SELECT id, name FROM users"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      mounted = console_actions(scope)
      assert length(mounted) == 2

      render_click(view, "sort_results", %{"sort" => "name"})
      assert [sorted] = console_actions(scope) -- mounted
      assert sorted.payload["result"] == "succeeded"

      render_click(view, "page_results", %{"page" => "1"})
      assert [_sorted, paged] = console_actions(scope) -- mounted
      assert paged.payload["result"] == "succeeded"
    end

    test "result page and page size round-trip through the URL without dropping unsaved SQL", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Series",
          sql_query: "SELECT * FROM generate_series(1, 30)"
        })

      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> live(~p"/admin/system/database-queries/#{query.slug}?page=2&page_size=25")

      assert has_element?(
               view,
               "#query-results-pagination-summary",
               "Showing 26 to 30 of 30 results"
             )

      assert has_element?(view, "#query-results-pagination-page-2[aria-current='page']")
      assert has_element?(view, "#result-row-0", "26")

      # An unsaved edit stays on the process when the pager patches the URL.
      # The saved statement still returns 30 rows; this one returns 5.
      view
      |> form("#query-sql-form", %{sql_query: "SELECT * FROM generate_series(1, 5)"})
      |> render_change()

      view |> element("#query-results-pagination-previous") |> render_click()

      patched = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert patched["page"] == "1"
      assert patched["page_size"] == "25"
      assert has_element?(view, "#query-sql-form textarea", "generate_series(1, 5)")

      assert has_element?(
               view,
               "#query-results-pagination-summary",
               "Showing 1 to 5 of 5 results"
             )

      view
      |> form("#query-results-pagination-page-size-form", %{"results" => %{"perPage" => "50"}})
      |> render_change()

      sized = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert sized["page"] == "1"
      assert sized["page_size"] == "50"
      assert has_element?(view, "#query-sql-form textarea", "generate_series(1, 5)")

      assert has_element?(
               view,
               "#query-results-pagination-summary",
               "Showing 1 to 5 of 5 results"
             )

      {:ok, reloaded, _html} =
        conn
        |> log_in_as()
        |> live(~p"/admin/system/database-queries/#{query.slug}?page=1&page_size=50")

      assert has_element?(
               reloaded,
               "#query-results-pagination-page-size option[value='50'][selected]"
             )

      assert has_element?(
               reloaded,
               "#query-results-pagination-summary",
               "Showing 1 to 30 of 30 results"
             )
    end

    test "a result page past the last page lands on the last page, and Run returns the URL to page one",
         %{conn: conn, scope: scope} do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Series",
          sql_query: "SELECT * FROM generate_series(1, 30)"
        })

      conn = log_in_as(conn)

      assert {:error, {:live_redirect, %{to: clamped_path}}} =
               live(conn, ~p"/admin/system/database-queries/#{query.slug}?page=9&page_size=25")

      clamped = clamped_path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert clamped["page"] == "2"

      {:ok, view, _html} = live(conn, clamped_path)

      assert has_element?(
               view,
               "#query-results-pagination-summary",
               "Showing 26 to 30 of 30 results"
             )

      view
      |> form("#query-sql-form", %{sql_query: "SELECT * FROM generate_series(1, 5)"})
      |> render_change()

      view |> element("#btn-run-query") |> render_click()

      ran = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert ran["page"] == "1"

      assert has_element?(
               view,
               "#query-results-pagination-summary",
               "Showing 1 to 5 of 5 results"
             )
    end

    test "renders the result set through the shared table, one sort button per column", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Header Roles",
          sql_query: "SELECT id, name FROM users;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      # Every section is a named region under the shared heading; the raw
      # section glyphs are gone with the hand-written headings.
      for id <- ~w(prompt sql-editor query-results) do
        assert has_element?(
                 view,
                 "##{id}-card[role='region'][aria-labelledby='#{id}-heading'] h2##{id}-heading"
               )
      end

      assert has_element?(view, "#sql-editor-card #btn-run-query", "Run Query")
      assert has_element?(view, "#query-results-summary", "2 columns")
      assert has_element?(view, "#query-results-card caption", "Query results")

      # `theme_contrast_test.exs` gates `ink-subtle` against `surface-sunken`
      # because that is the pair the shared `<.table>` head renders, and this
      # console renders that head rather than a hand-written one (parity
      # finding C2).
      head_classes =
        view |> element("#query-results-card thead") |> render() |> opening_tag_classes()

      cell_classes =
        view
        |> element("#query-results-card thead th:first-child")
        |> render()
        |> opening_tag_classes()

      assert "bg-surface-sunken" in head_classes
      assert "text-ink-subtle" in cell_classes

      # The columns come from the result set, each a sort button that reports
      # its state; sorting reruns the query through the page.
      assert has_element?(
               view,
               "th[aria-sort='none'] button#query-results-table-sort-name",
               "name"
             )

      assert has_element?(view, "#query-results-table-rows tr#result-row-0", "Ada Lovelace")

      view |> element("#query-results-table-sort-name") |> render_click()
      assert has_element?(view, "th[aria-sort='ascending'] #query-results-table-sort-name")

      view |> element("#query-results-table-sort-name") |> render_click()
      assert has_element?(view, "th[aria-sort='descending'] #query-results-table-sort-name")

      refute has_element?(view, "#query-results-card table.font-mono")
    end

    test "says when a query matched nothing", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Nobody",
          sql_query: "SELECT id FROM users WHERE id = -1;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(view, "#query-results-table-empty", "No rows returned")
      assert has_element?(view, "#query-results-table-empty", "matched nothing")
    end

    test "handles execution errors gracefully", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "Bad Query",
          description: "Syntax error query",
          sql_query: "SELECT invalid_column_xyz FROM non_existent_table;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(view, "#query-execution-error", "does not exist")
    end

    test "deletes existing query when user has edit capability", %{conn: conn, scope: scope} do
      grant_capabilities!([
        "admin.system.database-table.list",
        "admin.system.database-table.edit"
      ])

      {:ok, query} =
        User.create_database_query(as(scope, 91), %{
          name: "To Delete",
          sql_query: "SELECT 1;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      # Deleting a saved query confirms through the shared dialog; cancelling
      # keeps it on its page and confirming leaves for the list.
      assert has_element?(view, "#btn-delete-query")
      refute has_element?(view, "#btn-delete-query[data-confirm]")
      view |> element("#btn-delete-query") |> render_click()

      assert_modal_dialog(view, "delete-query-confirm", "Query “To Delete” will be deleted.")
      assert has_element?(view, "dialog#delete-query-confirm[role='alertdialog']")

      assert has_element?(
               view,
               "#delete-query-confirm-description",
               "Its saved SQL and parameters are removed. This cannot be undone."
             )

      view |> element("#delete-query-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#delete-query-confirm")
      assert {:ok, _} = User.get_database_query(as(scope, 91), query.slug)

      view |> element("#btn-delete-query") |> render_click()

      assert has_element?(
               view,
               "#delete-query-confirm-confirm[phx-disable-with='Deleting…']",
               "Delete"
             )

      view |> element("#delete-query-confirm-confirm") |> render_click()
      assert_redirect(view, ~p"/admin/system/database-queries")

      assert {:error, :not_found} = User.get_database_query(as(scope, 91), query.slug)
    end
  end

  defp console_actions(scope) do
    {:ok, actions} = Audit.list_actions(scope)
    Enum.filter(actions, &String.starts_with?(&1.event, "database_query."))
  end

  defp opening_tag_classes(html) do
    [opening_tag, _] = String.split(html, ">", parts: 2)
    [_, class_attribute] = Regex.run(~r/class="([^"]*)"/, opening_tag)

    String.split(class_attribute, ~r/\s+/, trim: true)
  end

  defp as(scope, user_id) do
    Bilimbi.Base.Tenancy.Authentication.sign_in(scope, user_id, 73)
  end
end
