defmodule Bilimbi.Base.Grid.Web.GridLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @all ~w(admin.user.list admin.company.list admin.employee.list admin.employee-type.list)

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

    UserFixtures.insert_user!(%{
      id: 93,
      company_id: 73,
      name: "Linus Pauling",
      email: "linus@example.com"
    })

    :ok
  end

  test "the page needs a signed-in account", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/grid")
  end

  test "the index lists only the tables the account may read", %{conn: conn} do
    grant_capabilities!(~w(admin.company.list))
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid")

    assert has_element?(view, "#grid-table-companies", "Companies")
    assert has_element?(view, "#grid-table-departments")
    refute has_element?(view, "#grid-table-users")
  end

  test "a table outside the catalog sends the account back to the index", %{conn: conn} do
    grant_capabilities!(~w(admin.company.list))
    conn = log_in_as(conn)

    assert {:error, {:live_redirect, %{to: "/grid", flash: flash}}} = live(conn, ~p"/grid/users")
    assert flash["error"] =~ "not in your catalog"
  end

  test "a table opens with its own fields and rows in the full mode", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users")

    assert has_element?(view, "#grid-chip-name", "Name")
    assert has_element?(view, "#grid-chip-email", "Email")
    assert has_element?(view, "#grid-head-created_at")
    assert has_element?(view, "#grid-row-91")
    assert has_element?(view, "#grid-cell-91-email", "ada@example.com")
    assert has_element?(view, "#grid-pagination-summary", "Showing 1 to 3 of 3 results")
    assert has_element?(view, "#grid-zoom-full[aria-pressed='true']")
    refute has_element?(view, "#grid-canvas")
  end

  test "typing in the add bar suggests walked columns, and picking one adds it to the URL", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users")

    view |> form("#grid-add-column", %{add: "company name"}) |> render_change()
    assert has_element?(view, "#grid-suggest-company-name", "Company › Name")
    assert has_element?(view, "#grid-suggest-company-parent-name")

    view |> element("#grid-suggest-company-name") |> render_click()

    assert_patch(
      view,
      ~p"/grid/users?cols=id%2Cname%2Cemail%2Cemail_verified_at%2Ccreated_at%2Cupdated_at%2Ccompany.name"
    )

    assert has_element?(view, "#grid-chip-company-name", "Name")
    assert has_element?(view, "#grid-head-company-name[title='Company › Name']")
    assert has_element?(view, "#grid-cell-91-company-name", "Bilimbi Industries")
    assert has_element?(view, "#grid-cell-92-company-name", "Bilimbi Retail")
    refute has_element?(view, "#grid-suggestions")
  end

  test "a typed spec adds on Enter, and a spec outside the catalog is left out with a message", %{
    conn: conn
  } do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")

    view
    |> form("#grid-add-column", %{add: "company.parent.name"})
    |> render_submit(%{"op" => "add_typed"})

    assert_patch(view, ~p"/grid/users?cols=name%2Ccompany.parent.name")
    assert has_element?(view, "#grid-cell-92-company-parent-name", "Bilimbi Industries")

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cnope.here")
    assert html =~ "Left out: nope.here"
    assert has_element?(view, "#grid-chip-name")
    refute has_element?(view, "#grid-chip-nope-here")
  end

  test "columns are removed and reordered, and the URL follows", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail%2Ccompany.name")

    view |> element("#grid-remove-email") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Ccompany.name")
    refute has_element?(view, "#grid-chip-email")

    render_hook(view, "grid", %{"op" => "move", "spec" => "company.name", "before" => "name"})
    assert_patch(view, ~p"/grid/users?cols=company.name%2Cname")
  end

  test "a rollup column counts, sorts, and expands in place", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Ccompany.users%3Acount")

    assert has_element?(view, "#grid-cell-91-company-users_count", "2")
    assert has_element?(view, "#grid-cell-92-company-users_count", "1")

    view |> element("#grid-sort-company-users_count") |> render_click()

    assert_patch(
      view,
      ~p"/grid/users?cols=name%2Ccompany.users%3Acount&sort=company.users%3Acount"
    )

    assert has_element?(view, "#grid-head-company-users_count[aria-sort='ascending']")

    view |> element("#grid-expand-91-company-users_count") |> render_click()
    assert has_element?(view, "#grid-row-91-company-users_count", "ada@example.com")
    assert has_element?(view, "#grid-row-91-company-users_count", "linus@example.com")
    assert has_element?(view, "#grid-expand-91-company-users_count[aria-expanded='true']")

    view |> element("#grid-expand-91-company-users_count") |> render_click()
    refute has_element?(view, "#grid-row-91-company-users_count")
  end

  test "a lens paints bands into the cells and lives in the URL", %{conn: conn} do
    grant_capabilities!(@all)

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/grid/companies?cols=name%2Cusers%3Acount")

    view |> element("#grid-lens-users_count-band") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cband")

    assert has_element?(
             view,
             "#grid-cell-73-users_count[data-scale='sequential'][data-band='4']",
             "2"
           )

    assert has_element?(view, "#grid-cell-74-users_count[data-band='0']", "1")

    view |> element("#grid-lens-users_count-bar") |> render_click()
    assert_patch(view, ~p"/grid/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cbar")
    assert has_element?(view, "#grid-cell-73-users_count [data-bar='100']")
  end

  test "zooming out switches to the canvas, and windows are served on request", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail")

    view |> element("#grid-zoom-carpet") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=3")
    assert has_element?(view, "#grid-canvas")
    assert has_element?(view, "#grid-zoom-carpet[aria-pressed='true']")
    assert has_element?(view, "#grid-window-summary", "3 rows by 2 columns")
    refute has_element?(view, "#grid-pagination")

    render_hook(view, "grid", %{
      "op" => "window",
      "offset" => 0,
      "limit" => 50,
      "detail" => "levels"
    })

    assert_push_event(view, "grid:window", %{offset: 0, total: 3, rows: rows})
    assert [[91, [[nil, _n, _band, :categorical], _email]], [92, _], [93, _]] = rows

    assert render_hook(view, "grid", %{"op" => "cell", "row" => 1, "col" => "email"}) =~
             "grid-canvas"

    view |> element("#grid-zoom-in") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=4")
  end

  test "a dragged rectangle zooms to fit it, back to the table when it is small", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name%2Cemail&z=3")

    render_hook(view, "grid", %{
      "op" => "zoom_rect",
      "from_row" => 0,
      "to_row" => 3,
      "from_col" => 0,
      "to_col" => 2,
      "width" => 1200,
      "height" => 600
    })

    assert_patch(view, ~p"/grid/users?cols=name%2Cemail&z=40")
    refute has_element?(view, "#grid-canvas")
  end

  test "search, page size and grouping keep to the URL", %{conn: conn} do
    grant_capabilities!(@all)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/grid/users?cols=name")

    view |> form("#grid-filters", %{filters: %{search: "grace"}}) |> render_change()
    assert_patch(view, ~p"/grid/users?cols=name&q=grace")
    assert has_element?(view, "#grid-row-92")
    refute has_element?(view, "#grid-row-91")

    view |> form("#grid-filters", %{filters: %{search: "nobody here"}}) |> render_change()
    assert_patch(view, ~p"/grid/users?cols=name&q=nobody+here")
    assert has_element?(view, "#grid-empty", "No rows match")

    view |> element("#grid-clear-search") |> render_click()
    assert_patch(view, ~p"/grid/users?cols=name")

    render_hook(view, "grid", %{"op" => "group", "spec" => "name"})
    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query) == %{
             "cols" => "name",
             "sort" => "name",
             "group" => "name"
           }

    assert has_element?(view, "#grid-grouped", "Grouped by name")
  end
end
