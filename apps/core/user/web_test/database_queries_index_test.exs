defmodule BilimbiWeb.DatabaseQueriesIndexTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
        User.create_database_query(as(scope, 91), %{
          name: "Active Users",
          description: "List of active users in system",
          sql_query: "SELECT id, name, email FROM users;"
        })

      {:ok, q2} =
        User.create_database_query(as(scope, 91), %{
          name: "Company Directory",
          description: "All companies",
          sql_query: "SELECT id, name FROM companies;"
        })

      # Create query for Grace (92)
      {:ok, _q3} =
        User.create_database_query(as(scope, 92), %{
          name: "Secret Query",
          description: "Not Ada's query",
          sql_query: "SELECT 1;"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")

      assert has_element?(view, "#database-queries-index", "Database Queries")
      assert has_element?(view, "#query-row-#{q1.id}", "Active Users")
      assert has_element?(view, "#query-row-#{q2.id}", "Company Directory")
      refute has_element?(view, "#database-queries-table", "Secret Query")
      assert has_element?(view, "#database-queries-table")
      assert has_element?(view, "#database-queries-table-sort-updated_at")
      assert has_element?(view, "#database-queries-card [aria-sort=descending]")
      refute has_element?(view, "#database-queries-card [class*=uppercase]")

      # Refute create button and row action buttons for read-only user
      refute has_element?(view, "#btn-create-query")
      refute has_element?(view, "#duplicate-query-#{q1.id}")
      refute has_element?(view, "#delete-query-#{q2.id}")

      # Unauthorized event attempts fail server-side
      render_click(view, "delete", %{"id" => to_string(q2.id)})
      assert has_element?(view, "#flash-error", "You are not authorized to modify queries.")

      assert {:ok, _} = User.get_database_query(as(scope, 91), q2.slug)

      render_click(view, "duplicate", %{"id" => to_string(q1.id)})
      assert has_element?(view, "#flash-error", "You are not authorized to modify queries.")

      # Test search
      view
      |> form("#database-queries-filters", %{"filters" => %{"search" => "Directory"}})
      |> render_change()

      assert has_element?(view, "#query-row-#{q2.id}")
      refute has_element?(view, "#query-row-#{q1.id}")

      patched = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert patched["search"] == "Directory"
      assert patched["page"] == "1"
      assert patched["page_size"] == "25"
    end

    test "search and page size round-trip through the URL", %{conn: conn, scope: scope} do
      grant_capabilities!("admin.system.database-table.list")

      for index <- 1..26 do
        {:ok, _query} =
          User.create_database_query(as(scope, 91), %{
            name: "Query #{String.pad_leading(Integer.to_string(index), 2, "0")}",
            sql_query: "SELECT #{index};"
          })
      end

      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> live(
          ~p"/admin/system/database-queries?search=Query&sort_by=name&sort_dir=asc&page_size=25"
        )

      assert has_element?(
               view,
               "#database-queries-pagination-summary",
               "Showing 1 to 25 of 26 results"
             )

      assert has_element?(view, "#search-input[value='Query']")

      assert has_element?(
               view,
               "#database-queries-pagination-page-size option[value='25'][selected]"
             )

      assert has_element?(view, "#database-queries-table", "Query 01")
      refute has_element?(view, "#database-queries-table", "Query 26")

      view |> element("#database-queries-pagination-next") |> render_click()

      page_two = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert page_two["search"] == "Query"
      assert page_two["sort_by"] == "name"
      assert page_two["page"] == "2"
      assert page_two["page_size"] == "25"
      assert has_element?(view, "#database-queries-table", "Query 26")
      refute has_element?(view, "#database-queries-table", "Query 01")

      {:ok, reloaded, _html} =
        conn
        |> log_in_as()
        |> live(
          ~p"/admin/system/database-queries?search=Query&sort_by=name&sort_dir=asc&page=2&page_size=25"
        )

      assert has_element?(
               reloaded,
               "#database-queries-pagination-summary",
               "Showing 26 to 26 of 26 results"
             )

      assert has_element?(reloaded, "#search-input[value='Query']")
      assert has_element?(reloaded, "#database-queries-table", "Query 26")
      refute has_element?(reloaded, "#database-queries-table", "Query 01")

      reloaded
      |> form("#database-queries-pagination-page-size-form", %{
        "filters" => %{"perPage" => "50"}
      })
      |> render_change()

      sized = assert_patch(reloaded) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert sized["search"] == "Query"
      assert sized["sort_by"] == "name"
      assert sized["page"] == "1"
      assert sized["page_size"] == "50"

      {:ok, widened, _html} =
        conn
        |> log_in_as()
        |> live(
          ~p"/admin/system/database-queries?search=Query&sort_by=name&sort_dir=asc&page=1&page_size=50"
        )

      assert has_element?(
               widened,
               "#database-queries-pagination-summary",
               "Showing 1 to 26 of 26 results"
             )

      assert has_element?(
               widened,
               "#database-queries-pagination-page-size option[value='50'][selected]"
             )

      assert has_element?(widened, "#database-queries-table", "Query 01")
      assert has_element?(widened, "#database-queries-table", "Query 26")
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
        User.create_database_query(as(scope, 91), %{
          name: "Active Users",
          description: "List of active users in system",
          sql_query: "SELECT id, name, email FROM users;"
        })

      {:ok, q2} =
        User.create_database_query(as(scope, 91), %{
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
      assert {:ok, _dup} = User.get_database_query(as(scope, 91), dup_slug)

      # Deleting confirms through the shared dialog, which names the query and
      # says what is lost; no native confirm remains.
      {:ok, view2, _} = conn |> log_in_as() |> live(~p"/admin/system/database-queries")

      # A confirm with nothing held is a stale click and deletes nothing.
      render_click(view2, "delete", %{"id" => to_string(q2.id)})
      assert {:ok, _} = User.get_database_query(as(scope, 91), q2.slug)

      refute has_element?(view2, "#delete-query-#{q2.id}[data-confirm]")
      view2 |> element("#delete-query-#{q2.id}") |> render_click()

      assert_modal_dialog(
        view2,
        "delete-query-confirm",
        "Query “Company Directory” will be deleted."
      )

      assert has_element?(view2, "dialog#delete-query-confirm[role='alertdialog']")

      assert has_element?(
               view2,
               "#delete-query-confirm-description",
               "Its saved SQL and parameters are removed. This cannot be undone."
             )

      # Cancelling keeps the query.
      view2 |> element("#delete-query-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view2, "#delete-query-confirm")
      assert has_element?(view2, "#query-row-#{q2.id}", "Company Directory")

      # Confirming deletes it and reports the completed write as a success.
      view2 |> element("#delete-query-#{q2.id}") |> render_click()

      assert has_element?(
               view2,
               "#delete-query-confirm-confirm[phx-disable-with='Deleting…']",
               "Delete"
             )

      view2 |> element("#delete-query-confirm-confirm") |> render_click()
      refute has_element?(view2, "#delete-query-confirm")
      assert has_element?(view2, "#flash-success", "Query “Company Directory” was deleted.")
      refute has_element?(view2, "#database-queries-table", "Company Directory")
      assert {:error, :not_found} = User.get_database_query(as(scope, 91), q2.slug)
    end
  end

  defp as(scope, user_id) do
    Bilimbi.Base.Tenancy.Authentication.sign_in(scope, user_id, 73)
  end
end
