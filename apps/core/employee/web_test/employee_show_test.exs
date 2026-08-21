defmodule BilimbiWeb.EmployeeShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
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

  # The link path had no coverage at all, and it was where #409 lived: a
  # `rescue _ -> {:ok, nil}` around the write meant every failure flashed
  # success. Both of these assert the store, because the flash was the thing
  # that lied.
  test "links a user account and records it in the database", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    view
    |> element("#employee-user-form")
    |> render_change(%{"user_id" => "91"})

    assert has_element?(view, "#flash-group", "User link updated.")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{employee_id: linked}} = User.get_user(scope, 73, 91)
    assert linked == employee.id
  end

  test "refuses to link a user from another company and writes nothing", %{
    conn: conn,
    employee: employee
  } do
    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Logistics",
      code: "bilimbi_logistics"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # User 92 is never an option in the select. Forging the event is the point:
    # a control that is not rendered is not a guard.
    view
    |> element("#employee-user-form")
    |> render_change(%{"user_id" => "92"})

    assert has_element?(view, "#flash-group", "Failed to update linked user account.")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{employee_id: nil}} = User.get_user(scope, 74, 92)
  end
end
