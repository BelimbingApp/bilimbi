defmodule Bilimbi.Core.UserAdministration.Web.GridColumnsTest do
  @moduledoc """
  The users list keeps its own query, filters, sort and pagination, and
  gains walked columns from the grid catalog beside its built-in ones.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_departments_table!()
    CompanyFixtures.create_department_types_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Bilimbi Industries"})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Retail",
      code: "bilimbi_retail",
      parent_id: 73
    })

    CompanyFixtures.assign_primary_company!(41, 73)

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(~w(admin.user.list admin.user.view admin.company.list))
    :ok
  end

  test "the built-in columns and their sort ids are unchanged", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users-chip-name", "Name")
    assert has_element?(view, "#users-chip-roles", "Roles")
    assert has_element?(view, "#users-sort-name")
    assert has_element?(view, "#users-sort-company")
    assert has_element?(view, "#user-91 #user-91-show", "Ada Lovelace")
    assert has_element?(view, "#user-created-91")

    view |> element("#users-sort-email") |> render_click()
    path = assert_patch(view)
    query = URI.decode_query(URI.parse(path).query)
    assert query["sortBy"] == "email" and query["sortDir"] == "asc"
    refute Map.has_key?(query, "cols")
  end

  test "a walked column is added from the bar, fetched for the listed rows, and kept in the URL",
       %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    view |> form("#users-add-column", %{add: "parent"}) |> render_change()

    assert has_element?(
             view,
             "#users-suggest-company-parent-name",
             "Company › Parent company › Name"
           )

    view |> element("#users-suggest-company-parent-name") |> render_click()
    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query)["cols"] ==
             "name,email,company_name,roles,created_at,company.parent.name"

    assert has_element?(view, "#users-chip-company-parent-name")
    assert has_element?(view, "#users-cell-92-company-parent-name", "Bilimbi Industries")
    assert has_element?(view, "#users-cell-91-company-parent-name", "—")
    assert has_element?(view, "#user-91 #user-91-show", "Ada Lovelace")

    # Walked columns are not sortable here: the page's own query sorts.
    refute has_element?(view, "#users-sort-company-parent-name")

    # The page's own controls keep the walked column.
    view |> element("#users-sort-name") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["cols"] =~ "company.parent.name"
  end

  test "the add box offers columns to walk to, never one the page already shows", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    # On a fresh page the address names no columns, and Email is one the page
    # draws itself: picking it would add nothing, so it is not offered. The
    # email of the user's company is a different column and is.
    view |> form("#users-add-column", %{add: "email"}) |> render_change()
    refute has_element?(view, "#users-suggest-email")
    assert has_element?(view, "#users-suggest-company-email", "Company › Email")

    # Asking for a suggestion arranges nothing: the address still names no columns.
    view |> element("#users-sort-name") |> render_click()
    refute Map.has_key?(URI.decode_query(URI.parse(assert_patch(view)).query), "cols")

    # Once removed, the built-in is something to add again.
    view |> element("#users-remove-email") |> render_click()
    assert_patch(view)
    view |> form("#users-add-column", %{add: "email"}) |> render_change()
    assert has_element?(view, "#users-suggest-email", "Email")
  end

  test "a built-in column can be removed and a rollup expanded in place", %{conn: conn} do
    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/users?cols=name%2Ccompany.users%3Acount")

    refute has_element?(view, "#users-chip-email")
    assert has_element?(view, "#users-cell-91-company-users_count", "1")

    view |> element("#users-expand-91-company-users_count") |> render_click()
    assert has_element?(view, "#user-91-company-users_count", "ada@example.com")

    view |> element("#users-remove-company-users_count") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["cols"] == "name"
  end

  test "one toggle switches the list between normal and compact rows", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users[data-mode='normal']")
    assert has_element?(view, "#users-density[aria-pressed='false']")

    view |> element("#users-density") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["density"] == "compact"

    # Compact is the same table: the rows, their links and the sort stay.
    assert has_element?(view, "#users[data-mode='compact']")
    assert has_element?(view, "#users-density[aria-pressed='true']")
    assert has_element?(view, "#user-91 #user-91-show", "Ada Lovelace")
    assert has_element?(view, "#users-sort-name")
    assert has_element?(view, "#users-pagination")

    view |> element("#users-density") |> render_click()
    path = assert_patch(view)
    refute Map.has_key?(URI.decode_query(URI.parse(path).query || ""), "density")
    assert has_element?(view, "#users[data-mode='normal']")
  end

  test "the list opens the way the account left it, and an address that names columns wins",
       %{conn: conn} do
    conn = log_in_as(conn)
    {:ok, view, _html} = live(conn, ~p"/users")

    view |> form("#users-add-column", %{add: "parent"}) |> render_change()
    view |> element("#users-suggest-company-parent-name") |> render_click()
    assert_patch(view)
    view |> element("#users-density") |> render_click()
    assert_patch(view)

    # A later visit to the bare address: the walked column and the density
    # are back without the address saying so.
    {:ok, later, _html} = live(conn, ~p"/users")
    assert has_element?(later, "#users-chip-company-parent-name")
    assert has_element?(later, "#users-cell-92-company-parent-name", "Bilimbi Industries")
    assert has_element?(later, "#users[data-mode='compact']")

    # The page's own controls carry the arrangement into the address.
    later |> element("#users-sort-name") |> render_click()
    query = URI.decode_query(URI.parse(assert_patch(later)).query)
    assert query["cols"] =~ "company.parent.name" and query["density"] == "compact"

    # A shared link says what to show, and opening it changes nothing kept.
    {:ok, linked, _html} = live(conn, ~p"/users?cols=name")
    assert has_element?(linked, "#users-chip-name")
    refute has_element?(linked, "#users-chip-email")
    refute has_element?(linked, "#users-chip-company-parent-name")
    assert has_element?(linked, "#users[data-mode='normal']")

    {:ok, again, _html} = live(conn, ~p"/users")
    assert has_element?(again, "#users-chip-company-parent-name")
    assert has_element?(again, "#users[data-mode='compact']")

    # Going back to the page's own columns and rows forgets the arrangement.
    again |> element("#users-remove-company-parent-name") |> render_click()
    assert_patch(again)
    again |> element("#users-density") |> render_click()
    query = URI.decode_query(URI.parse(assert_patch(again)).query)
    refute Map.has_key?(query, "cols") or Map.has_key?(query, "density")

    {:ok, reset, _html} = live(conn, ~p"/users")
    refute has_element?(reset, "#users-chip-company-parent-name")
    assert has_element?(reset, "#users-chip-email")
    assert has_element?(reset, "#users[data-mode='normal']")
  end

  test "an arrangement belongs to the account that made it", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    view |> element("#users-density") |> render_click()
    assert_patch(view)

    UserFixtures.insert_user!(%{
      id: 96,
      company_id: 73,
      name: "Colleague",
      email: "colleague@example.com"
    })

    grant_capabilities!(~w(admin.user.list admin.company.list), user_id: 96)

    {:ok, theirs, _html} =
      conn |> log_in_as(%{"user_id" => 96, "company_id" => 73}) |> live(~p"/users")

    assert has_element?(theirs, "#users[data-mode='normal']")
  end

  test "an account whose catalog lacks the walked table still sees its list", %{conn: conn} do
    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 73,
      name: "Only Users",
      email: "only@example.com"
    })

    grant_capabilities!(~w(admin.user.list), user_id: 95)

    {:ok, view, _html} =
      conn
      |> log_in_as(%{"user_id" => 95, "company_id" => 73})
      |> live(~p"/users?cols=name%2Ccompany.parent.name")

    assert has_element?(view, "#users-chip-name")
    refute has_element?(view, "#users-chip-company-parent-name")
    assert has_element?(view, "#user-95")
  end
end
