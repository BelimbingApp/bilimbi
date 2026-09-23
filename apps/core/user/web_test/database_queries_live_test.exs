defmodule BilimbiWeb.DatabaseQueriesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_database_queries_table!()
    AuditFixtures.create_audit_tables!()
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

  describe "Index LiveView (/admin/system/database-queries)" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/system/database-queries")
    end

    test "redirects away when user lacks capability", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/admin/system/database-queries")
    end

    test "lists user database queries and allows search, and hides write actions without edit capability",
         %{
           conn: conn,
           scope: scope
         } do
      grant_capabilities!("admin.system.database-table.list")

      # Create queries for Ada (91)
      {:ok, q1} =
        User.create_database_query(scope, 91, %{
          name: "Active Users",
          description: "List of active users in system",
          sql_query: "SELECT id, name, email FROM users;"
        })

      {:ok, q2} =
        User.create_database_query(scope, 91, %{
          name: "Company Directory",
          description: "All companies",
          sql_query: "SELECT id, name FROM companies;"
        })

      # Create query for Grace (92)
      {:ok, _q3} =
        User.create_database_query(scope, 92, %{
          name: "Secret Query",
          description: "Not Ada's query",
          sql_query: "SELECT 1;"
        })

      {:ok, view, html} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")

      assert html =~ "Database Queries"
      assert html =~ "Active Users"
      assert html =~ "Company Directory"
      refute html =~ "Secret Query"
      table_html = view |> element("#database-queries-card") |> render()
      assert has_element?(view, "#database-queries-table")
      assert html =~ ~s(id="database-queries-table-sort-updated_at")
      assert html =~ ~s(aria-sort="descending")
      refute table_html =~ "uppercase"

      # Refute create button and row action buttons for read-only user
      refute has_element?(view, "#btn-create-query")
      refute has_element?(view, "#duplicate-query-#{q1.id}")
      refute has_element?(view, "#delete-query-#{q2.id}")

      # Unauthorized event attempts fail server-side
      assert render_click(view, "delete", %{"id" => to_string(q2.id)}) =~
               "You are not authorized to modify queries."

      assert {:ok, _} = User.get_database_query(scope, 91, q2.slug)

      assert render_click(view, "duplicate", %{"id" => to_string(q1.id)}) =~
               "You are not authorized to modify queries."

      # Test search
      search_html = view |> form("form", %{search: "Directory"}) |> render_change()
      assert search_html =~ "Company Directory"
      refute search_html =~ "Active Users"
    end

    test "allows duplicate and delete on index when user has edit capability", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!([
        "admin.system.database-table.list",
        "admin.system.database-table.edit"
      ])

      {:ok, q1} =
        User.create_database_query(scope, 91, %{
          name: "Active Users",
          description: "List of active users in system",
          sql_query: "SELECT id, name, email FROM users;"
        })

      {:ok, q2} =
        User.create_database_query(scope, 91, %{
          name: "Company Directory",
          description: "All companies",
          sql_query: "SELECT id, name FROM companies;"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")

      assert has_element?(view, "#btn-create-query")
      assert has_element?(view, "#duplicate-query-#{q1.id} .hero-document-duplicate")
      assert has_element?(view, "#delete-query-#{q2.id}")

      # Test duplicate
      dup_slug = "#{q1.slug}-copy"
      render_click(view, "duplicate", %{"id" => to_string(q1.id)})
      assert_redirect(view, ~p"/admin/system/database-queries/#{dup_slug}")
      assert {:ok, _dup} = User.get_database_query(scope, 91, dup_slug)

      # Test delete
      {:ok, view2, _} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")
      render_click(view2, "delete", %{"id" => to_string(q2.id)})
      refute render(view2) =~ "Company Directory"
      assert {:error, :not_found} = User.get_database_query(scope, 91, q2.slug)
    end
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
        User.create_database_query(scope, 91, %{
          name: "Read Only Query",
          description: "For viewing",
          sql_query: "SELECT id, name FROM users;"
        })

      {:ok, view, html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert html =~ "Read Only Query"
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
      assert render_click(view, "save") =~ "You are not authorized to modify queries."
      assert render_click(view, "duplicate") =~ "You are not authorized to modify queries."
      assert render_click(view, "delete") =~ "You are not authorized to modify queries."
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
        User.create_database_query(scope, 91, %{
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

      {:ok, view, html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/_new")

      assert html =~ "New Query"
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
      assert {:ok, created} = User.get_database_query(scope, 91, "all-users-query")
      assert created.name == "All Users Query"
      assert created.sql_query == "SELECT id, name FROM users;"
    end

    test "executes query, detects named parameters, records audit action, and displays results",
         %{
           conn: conn,
           scope: scope
         } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(scope, 91, %{
          name: "Find User By Name",
          description: "Search user by name parameter",
          sql_query: "SELECT id, name FROM users WHERE name = :user_name;"
        })

      {:ok, view, html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert html =~ "Find User By Name"
      assert html =~ ":user_name"

      # Set parameter value
      view
      |> form("#query-params-form", %{"user_name" => "Ada Lovelace"})
      |> render_change()

      # Run query
      result_html = view |> element("#btn-run-query") |> render_click()

      assert result_html =~ "Ada Lovelace"
      assert result_html =~ "1 total rows"

      # Verify audit record was created
      assert {:ok, actions} = Audit.list_actions(scope)

      assert Enum.any?(actions, fn a ->
               a.event == "database_query.executed" and
                 a.payload["name"] == "Find User By Name"
             end)
    end

    test "renders the result set through the shared table, one sort button per column", %{
      conn: conn,
      scope: scope
    } do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(scope, 91, %{
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
      assert has_element?(view, "th[aria-sort='none'] button#query-results-table-sort-name", "name")
      assert has_element?(view, "tbody#query-results-table tr#result-row-0", "Ada Lovelace")

      view |> element("#query-results-table-sort-name") |> render_click()
      assert has_element?(view, "th[aria-sort='ascending'] #query-results-table-sort-name")

      view |> element("#query-results-table-sort-name") |> render_click()
      assert has_element?(view, "th[aria-sort='descending'] #query-results-table-sort-name")

      refute has_element?(view, "#query-results-card table.font-mono")
    end

    test "says when a query matched nothing", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.system.database-table.list")

      {:ok, query} =
        User.create_database_query(scope, 91, %{
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
        User.create_database_query(scope, 91, %{
          name: "Bad Query",
          description: "Syntax error query",
          sql_query: "SELECT invalid_column_xyz FROM non_existent_table;"
        })

      {:ok, _view, html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert html =~ "does not exist" or html =~ "error"
    end

    test "deletes existing query when user has edit capability", %{conn: conn, scope: scope} do
      grant_capabilities!([
        "admin.system.database-table.list",
        "admin.system.database-table.edit"
      ])

      {:ok, query} =
        User.create_database_query(scope, 91, %{
          name: "To Delete",
          sql_query: "SELECT 1;"
        })

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/admin/system/database-queries/#{query.slug}")

      assert has_element?(view, "#btn-delete-query")
      view |> element("#btn-delete-query") |> render_click()
      assert_redirect(view, ~p"/admin/system/database-queries")

      assert {:error, :not_found} = User.get_database_query(scope, 91, query.slug)
    end
  end

  describe "operator-only gate (#650)" do
    setup do
      # A second tenant that is NOT the platform operator, with its own company
      # and user, so the console can be probed by a fully-capable non-operator.
      CompanyFixtures.insert_tenant!(%{
        id: 51,
        name: "Ordinary tenant",
        is_platform_operator: false
      })

      CompanyFixtures.insert_company!(%{
        id: 83,
        tenant_id: 51,
        name: "Ordinary Co",
        code: "ordinary_co"
      })

      UserFixtures.insert_user!(%{
        id: 95,
        company_id: 83,
        name: "Nadia Non-Operator",
        email: "nadia@example.com"
      })

      # Grant BOTH capabilities to the non-operator so the capability gate passes
      # and any refusal is isolated to the platform-operator tenant gate.
      grant_capabilities!(
        ["admin.system.database-table.list", "admin.system.database-table.edit"],
        tenant_id: 51,
        company_id: 83,
        user_id: 95
      )

      %{non_operator: session_user(%{"user_id" => 95, "company_id" => 83})}
    end

    test "a fully-capable non-operator is refused at the Index mount", %{
      conn: conn,
      non_operator: non_operator
    } do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as(non_operator) |> live(~p"/admin/system/database-queries")
    end

    test "a fully-capable non-operator is refused at the Show mount", %{
      conn: conn,
      non_operator: non_operator
    } do
      # The gate halts in on_mount, before the slug is ever looked up.
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn
               |> log_in_as(non_operator)
               |> live(~p"/admin/system/database-queries/any-query")
    end

    test "the executor fails closed on a forged execute, before touching the store" do
      # A query that would raise at the database if the guard ever let it run.
      sql = "SELECT * FROM __blb_absent_table_650"

      # Absent opt fails closed with the operator error — never a DB error, so
      # the store was not reached.
      assert {:error, msg} = Database.execute_readonly(sql, %{}, [])
      assert msg =~ "platform operator"

      # Explicit false is identical.
      assert {:error, ^msg} = Database.execute_readonly(sql, %{}, operator: false)

      # With the operator tenant asserted, the guard passes and the store IS
      # reached — proven by the error now coming from Postgres, not the gate.
      assert {:error, db_msg} = Database.execute_readonly(sql, %{}, operator: true)
      refute db_msg =~ "platform operator"
      assert db_msg =~ "does not exist"
    end
  end

  defp opening_tag_classes(html) do
    [opening_tag, _] = String.split(html, ">", parts: 2)
    [_, class_attribute] = Regex.run(~r/class="([^"]*)"/, opening_tag)

    String.split(class_attribute, ~r/\s+/, trim: true)
  end
end
