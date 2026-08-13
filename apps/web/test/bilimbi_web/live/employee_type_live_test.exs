defmodule BilimbiWeb.EmployeeTypeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employee-types")
  end

  test "redirects away when the actor lacks admin.employee-type.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employee-types")
  end

  test "lists system types", %{conn: conn} do
    grant_capabilities!("admin.employee-type.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    assert has_element?(view, "#employee-types td", "Full Time")
    assert has_element?(view, "#employee-types td", "Agent")
    refute has_element?(view, "#employee-type-new")
  end

  test "creates a custom type", %{conn: conn} do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/new")

    view
    |> form("#employee-type-form", employee_type: %{code: "seasonal", label: "Seasonal"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employee-types"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(index, "#employee-types td", "Seasonal")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, types} = Employee.list_employee_types(scope, 73)
    assert Enum.any?(types, &(&1.code == "seasonal" and not &1.is_system))
  end
end
