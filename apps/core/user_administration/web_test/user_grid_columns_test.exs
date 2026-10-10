defmodule Bilimbi.Core.UserAdministration.Web.GridColumnsTest do
  @moduledoc """
  The users list keeps its own query, filters, sort and pagination, and
  gains walked columns from the grid catalog beside its built-in ones.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy

  alias Bilimbi.Base.Authz

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

  test "the table sits straight in its card, where a workspace tile can fill it", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    # The shape the "list fill" rules in app.css name: card, its inner
    # block, the table frame, the scroll box, with the pager beside the
    # frame. A wrapper between any two hides the table from them.
    assert has_element?(
             view,
             "#users-index[data-page='list'] > #users-card[data-card] > * > #users[data-table-frame] > #users-viewport[data-table-region]"
           )

    assert has_element?(view, "#users-card > * > #users-pagination")
  end

  test "the add box offers columns to walk to, never one the page already shows", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    # On a fresh page the address names no columns, and Email is one the page
    # draws itself: picking it would add nothing, so it is not offered. The
    # email of the user's company is a different column and is.
    view |> form("#users-add-column", %{add: "email"}) |> render_change()
    refute has_element?(view, "#users-suggest-email")
    assert has_element?(view, "#users-suggest-company-email", "Company › Email")

    # Once an operator restricts the company email to a role this account
    # lacks, the walked column is no longer offered.
    {:ok, scope} = Tenancy.scope(41)
    grant_capabilities!("admin.authz.field.manage", user_id: 96)
    operator = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 96, 73)
    {:ok, _} = Authz.put_field_restriction(operator, "companies", "email", [])
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    view |> form("#users-add-column", %{add: "email"}) |> render_change()
    refute has_element?(view, "#users-suggest-company-email")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

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

  # A press on a zoom control is pushed by the `FlexTable` hook, as its
  # `data-zoom-op` says, so the test pushes what the hook would.
  defp press(view, control) do
    assert has_element?(view, control)
    [op] = view |> element(control) |> render() |> attribute("data-zoom-op")

    payload =
      %{"op" => op}
      |> put_attribute(view, control, "data-dir", "dir")
      |> put_attribute(view, control, "data-preset", "preset")

    render_hook(view, "grid", payload)
  end

  defp put_attribute(payload, view, control, attribute, key) do
    case view |> element(control) |> render() |> attribute(attribute) do
      [value] -> Map.put(payload, key, value)
      [] -> payload
    end
  end

  defp attribute(html, name) do
    case Regex.run(~r/\s#{name}="([^"]*)"/, html, capture: :all_but_first) do
      [value] -> [value]
      nil -> []
    end
  end

  defp query(view), do: URI.decode_query(URI.parse(assert_patch(view)).query || "")

  test "Compact and Normal are two row heights of the same list", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")

    assert has_element?(view, "#users[data-mode='normal'][data-zoom='32']")
    assert has_element?(view, "#users-zoom-normal[aria-pressed='true']")

    press(view, "#users-zoom-compact")
    assert query(view)["z"] == "18"

    # Compact is the same table: the rows, their links and the sort stay.
    assert has_element?(view, "#users[data-mode='compact'][data-zoom='18']")
    assert has_element?(view, "#users-zoom-compact[aria-pressed='true']")
    assert has_element?(view, "#user-91 #user-91-show", "Ada Lovelace")
    assert has_element?(view, "#users-sort-name")
    assert has_element?(view, "#users-pagination")

    press(view, "#users-zoom-normal")
    refute Map.has_key?(query(view), "z")
    assert has_element?(view, "#users[data-mode='normal'][data-zoom='32']")
  end

  test "the zoom steps one height at a time and stops at the ends of its range", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users?z=36")

    press(view, "#users-zoom-in")
    assert query(view)["z"] == "40"
    assert has_element?(view, "#users-zoom-level", "40 px")
    assert has_element?(view, "#users-zoom-in[disabled]")

    # Down from the tallest: 36, 32, then the tallest compact height.
    for expected <- ["36", nil, "26"] do
      press(view, "#users-zoom-out")
      assert query(view)["z"] == expected
    end

    assert has_element?(view, "#users[data-mode='compact']")

    {:ok, shortest, _html} = conn |> log_in_as() |> live(~p"/users?z=18")
    assert has_element?(shortest, "#users-zoom-out[disabled]")
    refute has_element?(shortest, "#users-zoom-in[disabled]")
  end

  test "a press on Normal lands at once on a list remembered as compact", %{conn: conn} do
    conn = log_in_as(conn)
    {:ok, first, _html} = live(conn, ~p"/users")
    press(first, "#users-zoom-compact")
    assert_patch(first)

    # A later visit: the address names nothing and the rows are compact,
    # because that is what was kept.
    {:ok, view, _html} = live(conn, ~p"/users")
    assert has_element?(view, "#users[data-mode='compact']")

    # Normal is the page's own, so the address it patches to names nothing
    # either. The rows must follow the press, not what was kept before it:
    # this is the press that used to snap back to compact.
    press(view, "#users-zoom-normal")
    refute Map.has_key?(query(view), "z")
    assert has_element?(view, "#users[data-mode='normal'][data-zoom='32']")
    assert has_element?(view, "#users-zoom-normal[aria-pressed='true']")

    # And it stays through the page's own controls, with nothing kept now.
    view |> element("#users-sort-email") |> render_click()
    assert_patch(view)
    assert has_element?(view, "#users[data-mode='normal']")

    # Compact twice is compact; Normal straight after is normal.
    press(view, "#users-zoom-compact")
    assert_patch(view)
    press(view, "#users-zoom-compact")
    assert has_element?(view, "#users[data-mode='compact']")
    press(view, "#users-zoom-normal")
    assert_patch(view)
    assert has_element?(view, "#users[data-mode='normal']")
  end

  test "the list opens the way the account left it, and an address that names columns wins",
       %{conn: conn} do
    conn = log_in_as(conn)
    {:ok, view, _html} = live(conn, ~p"/users")

    view |> form("#users-add-column", %{add: "parent"}) |> render_change()
    view |> element("#users-suggest-company-parent-name") |> render_click()
    assert_patch(view)
    press(view, "#users-zoom-compact")
    assert_patch(view)

    # A later visit to the bare address: the walked column and the row
    # height are back without the address saying so.
    {:ok, later, _html} = live(conn, ~p"/users")
    assert has_element?(later, "#users-chip-company-parent-name")
    assert has_element?(later, "#users-cell-92-company-parent-name", "Bilimbi Industries")
    assert has_element?(later, "#users[data-mode='compact']")

    # The page's own controls carry the arrangement into the address.
    later |> element("#users-sort-name") |> render_click()
    carried = query(later)
    assert carried["cols"] =~ "company.parent.name" and carried["z"] == "18"

    # A shared link says what to show, and opening it changes nothing kept.
    {:ok, linked, _html} = live(conn, ~p"/users?cols=name")
    assert has_element?(linked, "#users-chip-name")
    refute has_element?(linked, "#users-chip-email")
    refute has_element?(linked, "#users-chip-company-parent-name")
    assert has_element?(linked, "#users[data-mode='normal']")

    {:ok, again, _html} = live(conn, ~p"/users")
    assert has_element?(again, "#users-chip-company-parent-name")
    assert has_element?(again, "#users[data-mode='compact']")
  end

  test "reset returns the list to its own columns and rows and forgets what was kept", %{
    conn: conn
  } do
    conn = log_in_as(conn)
    {:ok, view, _html} = live(conn, ~p"/users")

    view |> form("#users-add-column", %{add: "parent"}) |> render_change()
    view |> element("#users-suggest-company-parent-name") |> render_click()
    assert_patch(view)
    view |> element("#users-remove-email") |> render_click()
    assert_patch(view)
    press(view, "#users-zoom-compact")
    assert_patch(view)

    view |> element("#users-reset", "Reset to default columns") |> render_click()
    reset = query(view)
    refute Enum.any?(~w(cols lens z since), &Map.has_key?(reset, &1))
    assert has_element?(view, "#users-chip-email")
    refute has_element?(view, "#users-chip-company-parent-name")
    assert has_element?(view, "#users[data-mode='normal']")

    # Nothing is kept any more: a fresh visit is the page's own list.
    {:ok, fresh, _html} = live(conn, ~p"/users")
    assert has_element?(fresh, "#users-chip-email")
    refute has_element?(fresh, "#users-chip-company-parent-name")
    assert has_element?(fresh, "#users[data-mode='normal']")
  end

  test "a removed column of the page's own can always be added back", %{conn: conn} do
    conn = log_in_as(conn)
    {:ok, view, _html} = live(conn, ~p"/users")

    # Roles is drawn by the page and is no field of the catalog.
    view |> element("#users-remove-roles") |> render_click()
    assert_patch(view)
    refute has_element?(view, "#users-chip-roles")

    # The removal is kept.
    {:ok, later, _html} = live(conn, ~p"/users")
    refute has_element?(later, "#users-chip-roles")
    refute has_element?(later, "#users-head-roles")

    # The add box offers it by its label, beside what the catalog offers.
    later |> form("#users-add-column", %{add: "rol"}) |> render_change()
    assert has_element?(later, "#users-suggest-roles", "Roles")

    later |> element("#users-suggest-roles") |> render_click()
    assert query(later)["cols"] == "name,email,company_name,created_at,roles"
    assert has_element?(later, "#users-chip-roles")
    assert has_element?(later, "#users-head-roles")

    # And typing its label and pressing Enter does the same.
    later |> element("#users-remove-company_name") |> render_click()
    assert_patch(later)

    later
    |> form("#users-add-column", %{add: "Company"})
    |> render_submit(%{"op" => "add_typed"})

    assert query(later)["cols"] == "name,email,created_at,roles,company_name"

    # Both are kept as arranged.
    {:ok, again, _html} = live(conn, ~p"/users")
    assert has_element?(again, "#users-chip-roles")
    assert has_element?(again, "#users-chip-company_name")
  end

  test "an arrangement belongs to the account that made it", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    press(view, "#users-zoom-compact")
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
