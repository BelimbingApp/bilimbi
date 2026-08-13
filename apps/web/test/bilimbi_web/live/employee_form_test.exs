defmodule BilimbiWeb.EmployeeFormTest do
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
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employees/new")
  end

  test "redirects away when the actor lacks admin.employee.create", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employees/new")
  end

  test "creates an employee through the domain API", %{conn: conn} do
    grant_capabilities!(["admin.employee.create", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/new")

    view
    |> form("#employee-form",
      employee: %{
        employee_number: "EMP-009",
        full_name: "Grace Hopper",
        employee_type: "full_time",
        status: "active"
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"^/employees/\d+$"

    {:ok, show, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(show, "h1", "Grace Hopper")
    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, [employee]} = Employee.list_employees(scope, 73)
    assert employee.full_name == "Grace Hopper"
    assert employee.employee_number == "EMP-009"
  end

  test "edits an employee", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe"
      })

    grant_capabilities!(["admin.employee.update", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}/edit")

    view
    |> form("#employee-form", employee: %{full_name: "John Richard Doe"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employees/#{employee.id}"

    {:ok, show, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(show, "h1", "John Richard Doe")
  end
end
