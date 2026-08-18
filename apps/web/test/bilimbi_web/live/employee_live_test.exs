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

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        short_name: "John",
        designation: "Engineer",
        email: "john@example.test"
      })

    %{employee: employee, scope: scope}
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

    assert has_element?(view, "#nav-admin-employee[aria-current='page']")
    assert has_element?(view, "#employees td", "John Doe")
    assert has_element?(view, "#employees td", "EMP-001")
    refute has_element?(view, "#employees td", "Grace Hopper")
    refute has_element?(view, "#employee-new")
  end

  test "shows a create action when the actor may create employees", %{conn: conn} do
    grant_capabilities!([
      "admin.employee.list",
      "admin.employee.create",
      "admin.employee-type.list"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employee-new")
    assert has_element?(view, "#employee-types")
  end

  test "shows empty state when company has no employees", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Empty Co",
      code: "empty-co"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 75,
      name: "Empty User",
      email: "empty@example.test"
    })

    grant_capabilities!("admin.employee.list", company_id: 75, user_id: 92)

    {:ok, view, _html} =
      conn
      |> log_in_as(%{"user_id" => 92, "company_id" => 75})
      |> live(~p"/employees")

    assert has_element?(view, "#employees-empty", "No employees found.")
  end

  test "filters employees by search term", %{conn: conn, scope: scope} do
    {:ok, _jane} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-002",
        full_name: "Jane Smith",
        designation: "Designer",
        email: "jane@example.test"
      })

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employees td", "John Doe")
    assert has_element?(view, "#employees td", "Jane Smith")

    view
    |> form("#employees-filters", %{"filters" => %{"search" => "Jane"}})
    |> render_change()

    assert has_element?(view, "#employees td", "Jane Smith")
    refute has_element?(view, "#employees td", "John Doe")

    view
    |> form("#employees-filters", %{"filters" => %{"search" => "Designer"}})
    |> render_change()

    assert has_element?(view, "#employees td", "Jane Smith")
    refute has_element?(view, "#employees td", "John Doe")
  end

  test "filters employees by human or agent type", %{conn: conn, scope: scope} do
    {:ok, _agent} =
      Employee.create_employee(scope, 73, %{
        employee_number: "BOT-001",
        full_name: "Agent Bilimbi",
        employee_type: "agent"
      })

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employees td", "John Doe")
    assert has_element?(view, "#employees td", "Agent Bilimbi")

    view
    |> form("#employees-filters", %{"filters" => %{"type_filter" => "agent"}})
    |> render_change()

    assert has_element?(view, "#employees td", "Agent Bilimbi")
    refute has_element?(view, "#employees td", "John Doe")

    view
    |> form("#employees-filters", %{"filters" => %{"type_filter" => "human"}})
    |> render_change()

    assert has_element?(view, "#employees td", "John Doe")
    refute has_element?(view, "#employees td", "Agent Bilimbi")
  end

  test "sorts employees by name, type, and status with aria-sort and verified row ordering", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _alice} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-002",
        full_name: "Alice Adams",
        status: "terminated"
      })

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    # Initial order is asc by name (Alice Adams before John Doe)
    html = render(view)
    assert html =~ ~r/Alice Adams.*John Doe/s
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-status")

    # Click sort on full_name to toggle to desc
    view |> element("#employees-sort-name") |> render_click()
    html = render(view)
    assert html =~ ~r/John Doe.*Alice Adams/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-status")

    # Click sort on status
    view |> element("#employees-sort-status") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-status")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")

    # Click sort on type
    view |> element("#employees-sort-type") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-type")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-status")
  end

  test "paginates employee index with 25 rows per page and clamps out of bounds page", %{
    conn: conn,
    scope: scope
  } do
    for i <- 2..27 do
      num = String.pad_leading("#{i}", 3, "0")

      {:ok, _emp} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-#{num}",
          full_name: "Person #{num}"
        })
    end

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employees-pagination")
    assert has_element?(view, "#employees-pagination-summary", "Showing 1–25 of 27")
    assert has_element?(view, "#employees-pagination-position", "Page 1 of 2")
    assert has_element?(view, "#employees-pagination-previous[disabled]")

    # Navigate to page 2
    view |> element("#employees-pagination-next") |> render_click()

    assert has_element?(view, "#employees-pagination-summary", "Showing 26–27 of 27")
    assert has_element?(view, "#employees-pagination-position", "Page 2 of 2")
    assert has_element?(view, "#employees-pagination-next[disabled]")

    # Navigate to out-of-bounds page 999: automatically clamps to page 2
    {:ok, oob_view, _html} = conn |> log_in_as() |> live(~p"/employees?page=999")
    assert has_element?(oob_view, "#employees-pagination-position", "Page 2 of 2")
    assert has_element?(oob_view, "#employees-pagination-summary", "Showing 26–27 of 27")

    # Changing page size to 50 shows all 27 on page 1
    view
    |> form("#employees-filters", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert has_element?(view, "#employees-pagination-summary", "Showing 1–27 of 27")
    assert has_element?(view, "#employees-pagination-position", "Page 1 of 1")

    # Invalid per_page falls back to 25
    {:ok, invalid_view, _html} = conn |> log_in_as() |> live(~p"/employees?per_page=11")
    assert has_element?(invalid_view, "#employees-pagination-summary", "Showing 1–25 of 27")
  end

  test "deletes an employee when authorized", %{conn: conn, scope: scope} do
    {:ok, to_delete} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-999",
        full_name: "Temp Worker"
      })

    grant_capabilities!(["admin.employee.list", "admin.employee.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(view, "#employee-#{to_delete.id}-delete")

    view |> element("#employee-#{to_delete.id}-delete") |> render_click()

    assert render(view) =~ "Employee deleted successfully."
    refute has_element?(view, "#employees td", "Temp Worker")
  end

  test "renders show page with standard edit button", %{conn: conn, employee: employee} do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "h1", "John Doe")
    assert has_element?(view, "#employee-edit")
  end
end
