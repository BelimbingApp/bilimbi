defmodule BilimbiWeb.CompanyIndexLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Subsidiary",
      code: "bilimbi_subsidiary",
      parent_id: 73
    })

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    :ok
  end

  describe "Index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies")
    end

    test "redirects away when the actor lacks admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies")
    end

    test "lists only the current tenant's companies", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies td", "Bilimbi Industries")
      refute has_element?(view, "#companies td", "Elsewhere")
      refute has_element?(view, "#companies-add")
      assert has_element?(view, "#nav-admin-company[aria-current='page']")

      assert has_element?(
               view,
               "#nav-admin-company-department-type[href='/companies/department-types']"
             )

      assert has_element?(
               view,
               "#nav-admin-company-legal-entity-type[href='/companies/legal-entity-types']"
             )

      assert has_element?(view, "#nav-branch-admin[data-nav-default-expanded='true']")
      assert has_element?(view, "#nav-toggle-admin[aria-expanded='true']")
      assert has_element?(view, "#nav-children-admin:not([hidden])")
    end

    test "reaches the type lists through links carrying the demoted treatment, not a button's",
         %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(
               view,
               "a#companies-department-types[href='/companies/department-types'][title='Manage department types']",
               "Department Types"
             )

      assert has_element?(view, "#companies-department-types .hero-cog-6-tooth")

      assert has_element?(
               view,
               "a#companies-legal-entity-types[href='/companies/legal-entity-types'][title='Manage legal entity types']",
               "Legal Entity Types"
             )

      assert has_element?(view, "#companies-legal-entity-types .hero-cog-6-tooth")

      # A navigating <.button> renders an anchor too, so the tag proves
      # nothing; the treatment is what demotion changed.
      for id <- ~w(companies-department-types companies-legal-entity-types) do
        assert has_element?(view, "a##{id}.text-link")
        refute has_element?(view, "a##{id}.border")
        refute has_element?(view, "a##{id}.bg-action")
        refute has_element?(view, "a##{id}.shadow-sm")
      end

      # The page's own primary action keeps the button treatment; the type
      # lists are a related workflow, so they demote (DESIGN.md, "Demoted
      # secondary actions").
      assert has_element?(view, "main header a#companies-add.bg-action", "Add Company")
    end

    test "search, status filter, and sort live in the URL", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])
      conn = log_in_as(conn)

      {:ok, view, _html} = live(conn, ~p"/companies?search=Subsidiary")
      assert has_element?(view, "#companies td", "Bilimbi Subsidiary")
      refute has_element?(view, "#companies td a", "Bilimbi Industries")

      {:ok, view, _html} = live(conn, ~p"/companies?status=suspended")
      assert has_element?(view, "#companies-empty")

      {:ok, view, _html} = live(conn, ~p"/companies?sort=name&dir=desc")
      assert has_element?(view, "#companies-card [aria-sort=descending]")
      assert has_element?(view, "#companies tr:first-child td:first-child", "Bilimbi Subsidiary")
    end

    test "toolbar search and status filter round-trip through the URL", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])
      conn = log_in_as(conn)

      {:ok, view, _html} = live(conn, ~p"/companies")

      # The shared toolbar sends the same search a URL visit would carry.
      view
      |> form("#companies-filters",
        filters: %{"search" => "Subsidiary", "status_filter" => "all"}
      )
      |> render_change()

      assert_patch(view, ~p"/companies?search=Subsidiary")
      assert has_element?(view, "#companies td", "Bilimbi Subsidiary")
      refute has_element?(view, "#companies td a", "Bilimbi Industries")

      # The patched URL reloads to the same rows with the toolbar state retained.
      {:ok, reloaded, _html} = live(conn, ~p"/companies?search=Subsidiary")
      assert has_element?(reloaded, "#companies td", "Bilimbi Subsidiary")
      refute has_element?(reloaded, "#companies td a", "Bilimbi Industries")
      assert has_element?(reloaded, "#companies-search[value='Subsidiary']")

      # The shared toolbar sends the same status filter a URL visit would carry.
      reloaded
      |> form("#companies-filters", filters: %{"search" => "", "status_filter" => "suspended"})
      |> render_change()

      assert_patch(reloaded, ~p"/companies?status=suspended")
      assert has_element?(reloaded, "#companies-empty")

      {:ok, filtered, _html} = live(conn, ~p"/companies?status=suspended")
      assert has_element?(filtered, "#companies-empty")

      assert has_element?(
               filtered,
               "#companies-status-filter option[value='suspended'][selected]"
             )
    end

    test "renders parent, jurisdiction, primary badge, and pagination controls", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])
      CompanyFixtures.assign_primary_company!(41, 73)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies-search")
      assert has_element?(view, "#companies-status-filter")
      assert has_element?(view, "#companies-pagination")
      assert has_element?(view, "#companies-card th", "Parent")
      assert has_element?(view, "#companies-card th", "Jurisdiction")
      assert has_element?(view, "#companies", "Primary")
      assert has_element?(view, "#companies", "Bilimbi Industries")
    end

    test "a restricted jurisdiction reads Restricted, has no column, sort or search for a non-holder",
         %{conn: conn} do
      from(c in "companies", where: c.id == 73) |> Repo.update_all(set: [jurisdiction: "MY"])
      grant_capabilities!(["admin.company.list"])
      grant_capabilities!("admin.authz.field.manage", user_id: 92)
      {:ok, scope} = Tenancy.scope(41)
      operator = Tenancy.Authentication.sign_in(scope, 92, 73)
      {:ok, finance} = Authz.create_role(operator, 73, %{name: "Finance", code: "finance"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")
      assert has_element?(view, "#companies-card th", "Jurisdiction")
      assert has_element?(view, "#companies-sort-jurisdiction")
      assert has_element?(view, "#companies", "MY")

      {:ok, _} = Authz.put_field_restriction(operator, "companies", "jurisdiction", [finance.id])

      {:ok, view, html} = conn |> log_in_as() |> live(~p"/companies?sort=jurisdiction&dir=desc")
      refute html =~ "MY"
      refute has_element?(view, "#companies-card th", "Jurisdiction")
      refute has_element?(view, "#companies-sort-jurisdiction")
      assert has_element?(view, "#companies tr:first-child td:first-child", "Bilimbi Industries")

      refute has_element?(view, "#companies-search[placeholder*='jurisdiction']")
      assert has_element?(view, "#companies-search[placeholder*='legal name']")

      {:ok, _} = Authz.assign_role(operator, 73, :user, 91, finance.id)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies?sort=jurisdiction&dir=desc")
      assert has_element?(view, "#companies-card th", "Jurisdiction")
      assert has_element?(view, "#companies", "MY")
    end

    test "junk query parameters normalize to defaults", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> live(~p"/companies?sort=bogus&dir=sideways&page=-3&per_page=7&status=nope")

      assert has_element?(view, "#companies td", "Bilimbi Industries")
      assert has_element?(view, "#companies td", "Bilimbi Subsidiary")
    end

    test "an empty search says what matched nothing and offers to clear it", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/companies?search=zzz-no-such-company&sort=name&dir=desc")

      assert has_element?(view, "#companies-empty", "No companies match “zzz-no-such-company”")
      assert has_element?(view, "#companies-empty", "clear the search")
      refute has_element?(view, "#companies-empty", "No companies yet")

      view |> element("#companies-clear-search", "Clear search") |> render_click()

      assert_patch(view, ~p"/companies?dir=desc")
      assert has_element?(view, "#companies td", "Bilimbi Industries")
      refute has_element?(view, "#companies-empty")
    end

    test "an empty status filter names the status and offers every status", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])
      conn = log_in_as(conn)

      {:ok, view, _html} = live(conn, ~p"/companies?status=suspended")

      assert has_element?(view, "#companies-empty", "No suspended companies")
      assert has_element?(view, "#companies-empty", "has this status")

      view |> element("#companies-clear-search", "Show all statuses") |> render_click()
      assert_patch(view, ~p"/companies")
      assert has_element?(view, "#companies td", "Bilimbi Industries")

      {:ok, view, _html} = live(conn, ~p"/companies?status=suspended&search=zzz")

      assert has_element?(view, "#companies-empty", "No suspended companies match “zzz”")
      assert has_element?(view, "#companies-clear-search", "Clear search and filter")
    end

    # A signed-in actor's own company is always a live row of this list, so an
    # unfiltered empty page cannot be reached by a fresh request, and not by a
    # mounted view either: the host rehydrates the session before the next
    # patch, and an actor whose company is gone is signed out, not shown an
    # empty list.
    test "an actor whose company vanished is signed out at the next patch", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies?search=zzz")
      Repo.delete_all(from(c in "companies", where: c.tenant_id == 41))

      assert {:error, {:redirect, %{to: "/"}}} =
               view |> element("#companies-clear-search") |> render_click()

      assert assert_redirect(view, "/")["session_expired"] == "expired"
    end
  end
end
