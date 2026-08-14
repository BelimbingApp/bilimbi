defmodule BilimbiWeb.EmployeeShowTest do
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
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        email: "john@example.test"
      })

    %{employee: employee}
  end

  test "requires authentication", %{conn: conn, employee: employee} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employees/#{employee.id}")
  end

  test "redirects away when the actor lacks admin.employee.view", %{
    conn: conn,
    employee: employee
  } do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
  end

  test "shows the employee", %{conn: conn, employee: employee} do
    grant_capabilities!("admin.employee.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "h1", "John Doe")
    assert has_element?(view, "#app-content", "EMP-001")
    refute has_element?(view, "#employee-edit")
    refute has_element?(view, "#employee-danger")
  end

  test "hides the destructive action without admin.employee.delete", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    refute has_element?(view, "#employee-delete")
    assert has_element?(view, "#employee-edit")
  end

  test "deletes an ordinary employee", %{conn: conn, employee: employee} do
    grant_capabilities!([
      "admin.employee.list",
      "admin.employee.view",
      "admin.employee.delete"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    view |> element("#employee-delete") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path == "/employees"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    refute has_element?(index, "#employees td", "John Doe")
  end

  test "refuses to delete the platform orchestrator", %{conn: conn} do
    CompanyFixtures.assign_primary_company!(41, 73)
    {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    grant_capabilities!(["admin.employee.view", "admin.employee.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{orchestrator.id}")

    view |> element("#employee-delete") |> render_click()

    assert has_element?(view, "#flash-group", "The platform orchestrator cannot be deleted.")
    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, _} = Employee.get_employee(scope, 73, orchestrator.id)
  end
end
