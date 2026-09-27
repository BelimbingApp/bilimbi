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

  test "zooming out draws the page's rows on the canvas and serves them as a window", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users?cols=name%2Cemail&z=3")

    assert has_element?(view, "#users-canvas")
    assert has_element?(view, "#users-pagination")

    render_hook(view, "grid", %{
      "op" => "window",
      "id" => "users",
      "offset" => 0,
      "limit" => 50,
      "detail" => "text"
    })

    assert_push_event(view, "users:window", %{total: 2, rows: rows})

    assert [[91, [["Ada Lovelace", nil, nil, nil], ["ada@example.com", nil, nil, nil]]], [92, _]] =
             rows
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
