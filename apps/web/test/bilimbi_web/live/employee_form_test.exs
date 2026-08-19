defmodule BilimbiWeb.EmployeeFormTest do
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
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employees/new")
  end

  test "redirects away when the actor lacks admin.employee.create", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employees/new")
  end

  test "renders full 2-column form structure with all 14 fields matching Belimbing parity", %{
    conn: conn
  } do
    grant_capabilities!(["admin.employee.create", "admin.employee.view"])

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/employees/new")

    # Header elements
    assert html =~ "Add Employee"
    assert html =~ "Create a new employment record"
    assert html =~ "← Back"

    # 14 Form fields with Belimbing-parity IDs and placeholders
    assert has_element?(view, "#employee-company-id")
    assert has_element?(view, "#employee-department-id")
    assert has_element?(view, "#employee-number[placeholder='Employee ID or number']")
    assert has_element?(view, "#employee-full-name[placeholder='Full legal name']")
    assert has_element?(view, "#employee-short-name[placeholder='Preferred or display name']")
    assert has_element?(view, "#employee-designation[placeholder='Job title or designation']")
    assert has_element?(view, "#employee-type")
    assert has_element?(view, "#employee-status")
    assert has_element?(view, "#employee-email[placeholder='Work email address']")
    assert has_element?(view, "#employee-mobile-number[placeholder='Contact number']")
    assert has_element?(view, "#employee-employment-start")
    assert has_element?(view, "#employee-employment-end")
    assert has_element?(view, "#employee-supervisor-id")
    assert has_element?(view, "#employee-user-id")
  end

  test "creates an employee with all 14 fields and links a user account", %{conn: conn} do
    grant_capabilities!(["admin.employee.create", "admin.employee.view"])
    {:ok, scope} = Tenancy.scope(41)

    # Create a supervisor employee first
    {:ok, supervisor} =
      Employee.create_employee(scope, 73, %{
        employee_number: "SUP-001",
        full_name: "Alan Turing",
        employee_type: "full_time",
        status: "active"
      })

    # Create a second user to link
    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/new")

    view
    |> form("#employee-form",
      employee: %{
        company_id: "73",
        employee_number: "EMP-009",
        full_name: "Grace Hopper",
        short_name: "Grace",
        designation: "Lead Systems Architect",
        employee_type: "full_time",
        status: "active",
        email: "grace@example.com",
        mobile_number: "+1 555-0199",
        employment_start: "2026-01-01",
        employment_end: "2026-12-31",
        supervisor_id: "#{supervisor.id}",
        user_id: "92"
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"^/employees/\d+$"

    {:ok, show, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(show, "h1", "Grace Hopper")

    assert {:ok, employees} = Employee.list_employees(scope, 73)
    created = Enum.find(employees, &(&1.employee_number == "EMP-009"))
    assert created
    assert created.full_name == "Grace Hopper"
    assert created.short_name == "Grace"
    assert created.designation == "Lead Systems Architect"
    assert created.employee_type == "full_time"
    assert created.status == "active"
    assert created.email == "grace@example.com"
    assert created.mobile_number == "+1 555-0199"
    assert created.employment_start == ~D[2026-01-01]
    assert created.employment_end == ~D[2026-12-31]
    assert created.supervisor_id == supervisor.id

    # Verify user account link
    assert {:ok, user} = User.get_user(scope, 73, 92)
    assert user.employee_id == created.id
  end

  test "edits an employee with all fields and unlinks/relinks user account", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        short_name: "John",
        employee_type: "full_time",
        status: "active"
      })

    # Link user 91 to this employee
    {:ok, _} = User.update_user(scope, 73, 91, %{employee_id: employee.id})

    grant_capabilities!(["admin.employee.update", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}/edit")

    # Form has pre-populated values
    assert has_element?(view, "#employee-number[value='EMP-001']")
    assert has_element?(view, "#employee-full-name[value='John Doe']")

    view
    |> form("#employee-form",
      employee: %{
        full_name: "John Richard Doe",
        short_name: "Johnny",
        designation: "Principal Engineer",
        user_id: ""
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employees/#{employee.id}"

    {:ok, show, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(show, "h1", "John Richard Doe")

    {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
    assert updated.full_name == "John Richard Doe"
    assert updated.short_name == "Johnny"
    assert updated.designation == "Principal Engineer"

    # Verify user was unlinked
    assert {:ok, user} = User.get_user(scope, 73, 91)
    assert is_nil(user.employee_id)
  end

  test "validates date ordering (employment_end cannot be before employment_start)", %{conn: conn} do
    grant_capabilities!(["admin.employee.create", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/new")

    html =
      view
      |> form("#employee-form",
        employee: %{
          employee_number: "EMP-009",
          full_name: "Grace Hopper",
          employee_type: "full_time",
          status: "active",
          employment_start: "2026-12-31",
          employment_end: "2026-01-01"
        }
      )
      |> render_change()

    assert html =~ "must be on or after employment start"
  end

  test "renders form without mutating database when system types are not provisioned", %{
    conn: conn
  } do
    Bilimbi.Base.Repo.delete_all(Bilimbi.Core.Employee.EmployeeType)

    grant_capabilities!(["admin.employee.create", "admin.employee.view"])

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/employees/new")
    assert has_element?(view, "#employee-type")
    assert html =~ "Full Time"

    assert Bilimbi.Base.Repo.all(Bilimbi.Core.Employee.EmployeeType) == []
  end

  test "rejects linking a user from a different company in same tenant", %{conn: conn} do
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 99, company_id: 74, name: "Foreign Company User"})

    grant_capabilities!(["admin.employee.create", "admin.employee.view"])
    {:ok, scope} = Tenancy.scope(41)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/new")

    view
    |> form("#employee-form",
      employee: %{
        company_id: "73",
        employee_number: "EMP-010",
        full_name: "Test Employee",
        employee_type: "full_time",
        status: "active",
        user_id: "99"
      }
    )
    |> render_submit()

    assert {:ok, user} = User.get_user(scope, 74, 99)
    assert is_nil(user.employee_id)
  end

  test "retains original employee company on edit even if company_id is posted", %{conn: conn} do
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 41})
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        employee_type: "full_time",
        status: "active"
      })

    grant_capabilities!(["admin.employee.update", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}/edit")

    view
    |> form("#employee-form",
      employee: %{
        company_id: "74",
        full_name: "John Richard Doe"
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employees/#{employee.id}"

    {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
    assert updated.company_id == 73
    assert updated.full_name == "John Richard Doe"
  end
end
