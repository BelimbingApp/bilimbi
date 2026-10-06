defmodule Bilimbi.Core.Company.Web.GridColumnsTest do
  @moduledoc """
  The companies list keeps its own query, filters, sort and pagination, and
  gains walked columns and rollups from the grid catalog.
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
    CompanyFixtures.insert_department!(1, 73)

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

    grant_capabilities!(~w(admin.company.list admin.user.list))
    :ok
  end

  test "rollups count the company's people and departments beside the built-in columns", %{
    conn: conn
  } do
    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/companies?cols=name%2Cstatus%2Cusers%3Acount%2Cdepartments%3Acount")

    assert has_element?(view, "#companies-sort-name")
    assert has_element?(view, "#companies-sort-status")
    refute has_element?(view, "#companies-chip-code")
    assert has_element?(view, "#companies-cell-73-users_count", "2")
    assert has_element?(view, "#companies-cell-73-departments_count", "1")
    assert has_element?(view, "#companies-cell-74-users_count", "0")

    view |> element("#companies-expand-73-users_count") |> render_click()
    assert has_element?(view, "#companies-73-users_count", "grace@example.com")
  end

  test "a lens colours a rollup and the page's own filters keep the columns", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cband")

    # Two users in one company, none in the other: the range runs 0 to 2.
    assert has_element?(
             view,
             "#companies-cell-73-users_count[data-scale='sequential'][data-band='4']",
             "2"
           )

    assert has_element?(view, "#companies-cell-74-users_count[data-band='0']", "0")

    view |> form("#companies-filters", %{filters: %{search: "Retail"}}) |> render_change()
    path = assert_patch(view)
    query = URI.decode_query(URI.parse(path).query)
    assert query["search"] == "Retail"
    assert query["cols"] == "name,users:count"
    assert query["lens"] == "users:count|band"
    assert has_element?(view, "#companies-74")
    refute has_element?(view, "#companies-73")
  end

  test "a change-since lens compares against a date the reader sets", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/companies?cols=name%2Cusers%3Acount&lens=users%3Acount%7Cdelta")

    # Without a date in the address the lens compares against thirty days ago.
    assert has_element?(
             view,
             "#companies-since-input[value='#{Date.add(Date.utc_today(), -30)}']"
           )

    view |> form("#companies-since", %{since: "2026-01-01"}) |> render_change()
    query = URI.decode_query(URI.parse(assert_patch(view)).query)
    assert query["since"] == "2026-01-01"
    assert query["lens"] == "users:count|delta"
    assert has_element?(view, "#companies-since-input[value='2026-01-01']")

    # No column wears the lens: the control is gone.
    {:ok, plain, _html} = conn |> log_in_as() |> live(~p"/companies?cols=name%2Cusers%3Acount")
    refute has_element?(plain, "#companies-since")
  end

  test "compact rows drop the second line under a company's name", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      name: "Bilimbi Labs",
      code: "bilimbi_labs",
      legal_name: "Bilimbi Laboratories Sdn. Bhd."
    })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")
    assert has_element?(view, "#companies-76", "Bilimbi Laboratories Sdn. Bhd.")

    view |> element("#companies-density") |> render_click()
    assert_patch(view)
    assert has_element?(view, "#companies-76", "Bilimbi Labs")
    refute has_element?(view, "#companies-76", "Bilimbi Laboratories Sdn. Bhd.")
  end

  test "the add bar walks to the parent company and the primary address", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

    view |> form("#companies-add-column", %{add: "parent name"}) |> render_change()
    assert has_element?(view, "#companies-suggest-parent-name", "Parent company › Name")

    view
    |> form("#companies-add-column", %{add: "parent.name"})
    |> render_submit(%{"op" => "add_typed"})

    path = assert_patch(view)

    assert URI.decode_query(URI.parse(path).query)["cols"] ==
             "name,code,parent_name,status,jurisdiction,parent.name"

    assert has_element?(view, "#companies-cell-74-parent-name", "Bilimbi Industries")
  end
end
