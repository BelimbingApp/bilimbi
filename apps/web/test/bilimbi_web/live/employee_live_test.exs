defmodule BilimbiWeb.EmployeeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        short_name: "John",
        designation: "Engineer",
        email: "john@example.test"
      })

    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employees")
  end

  test "redirects away when the actor lacks admin.employee.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employees")
  end

  test "lists employees for the signed-in company only", %{conn: conn} do
    {:ok, other} = Tenancy.scope(42)

    {:ok, _elsewhere} =
      Employee.create_employee(other, 74, %{
        employee_number: "EMP-074",
        full_name: "Grace Hopper"
      })

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employees td", "John")
    assert has_element?(view, "#employees td", "EMP-001")
    refute has_element?(view, "#employees td", "Grace Hopper")
    refute has_element?(view, "#employee-new")
  end

  test "shows a create action when the actor may create employees", %{conn: conn} do
    grant_capabilities!(["admin.employee.list", "admin.employee.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employee-new")
  end
end
