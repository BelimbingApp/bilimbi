defmodule BilimbiWeb.EmployeeLiveTest do
  use BilimbiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bilimbi.Base.Authz.TestSupport

  alias Bilimbi.Core.Company.TestSupport, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestSupport, as: UserFixtures

  setup do
    company =
      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Acme Corp",
        code: "acme"
      })

    user =
      UserFixtures.insert_user!(%{
        id: 91,
        company_id: company.id,
        name: "Admin User",
        email: "admin@example.test"
      })

    scope = %{
      user: %{
        "id" => user.id,
        "company_id" => company.id,
        "company_name" => company.name,
        "tenant_id" => company.tenant_id
      },
      capabilities: []
    }

    employee =
      Employee.TestSupport.insert_employee!(%{
        company_id: company.id,
        employee_number: "EMP-001",
        full_name: "John Doe",
        designation: "Software Engineer",
        email: "john@example.test",
        status: "active",
        employee_type: "human"
      })

    %{company: company, user: user, scope: scope, employee: employee}
  end

  test "redirects guests to the login page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, ~p"/employees")
  end

  test "renders 403 when the actor lacks admin.employee.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in_as() |> live(~p"/employees")
  end

  test "renders employee index for authorized actors and highlights the navigation", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!("admin.employee.list")

    other_company =
      CompanyFixtures.insert_company!(%{
        id: 74,
        tenant_id: 41,
        name: "Other Co",
        code: "other"
      })

    Employee.TestSupport.insert_employee!(%{
      company_id: other_company.id,
      employee_number: "EMP-999",
      full_name: "Grace Hopper",
      designation: "Admiral",
      email: "grace@other.test",
      status: "active"
    })

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

  test "filters employees by search term and patches URL", %{conn: conn, scope: scope} do
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

    assert_patched(view, ~p"/employees?search=Jane")
    assert has_element?(view, "#employees td", "Jane Smith")
    refute has_element?(view, "#employees td", "John Doe")

    view
    |> form("#employees-filters", %{"filters" => %{"search" => "Designer"}})
    |> render_change()

    assert_patched(view, ~p"/employees?search=Designer")
    assert has_element?(view, "#employees td", "Jane Smith")
    refute has_element?(view, "#employees td", "John Doe")
  end

  test "filters employees by human or agent type and patches URL", %{conn: conn, scope: scope} do
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

    assert_patched(view, ~p"/employees?type=agent")
    assert has_element?(view, "#employees td", "Agent Bilimbi")
    refute has_element?(view, "#employees td", "John Doe")

    view
    |> form("#employees-filters", %{"filters" => %{"type_filter" => "human"}})
    |> render_change()

    assert_patched(view, ~p"/employees?type=human")
    assert has_element?(view, "#employees td", "John Doe")
    refute has_element?(view, "#employees td", "Agent Bilimbi")
  end

  test "sorts employees by name, type, and status with aria-sort, url patch, and verified row ordering", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _alice} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-002",
        full_name: "Alice Adams",
        status: "terminated",
        employee_type: "human"
      })

    {:ok, _bot} =
      Employee.create_employee(scope, 73, %{
        employee_number: "BOT-001",
        full_name: "Bot Baker",
        status: "probation",
        employee_type: "agent"
      })

    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    # Initial order is asc by name (Alice Adams -> Bot Baker -> John Doe)
    html = render(view)
    assert html =~ ~r/Alice Adams.*Bot Baker.*John Doe/s
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-status")

    # Click sort on full_name to toggle to desc
    view |> element("#employees-sort-name") |> render_click()
    assert_patched(view, ~p"/employees?dir=desc")
    html = render(view)
    assert html =~ ~r/John Doe.*Bot Baker.*Alice Adams/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-status")

    # Click sort on status (asc: active -> probation -> terminated)
    view |> element("#employees-sort-status") |> render_click()
    assert_patched(view, ~p"/employees?sort=status")
    html = render(view)
    assert html =~ ~r/John Doe.*Bot Baker.*Alice Adams/s
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-status")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #employees-sort-type")

    # Click sort on status again (desc: terminated -> probation -> active)
    view |> element("#employees-sort-status") |> render_click()
    assert_patched(view, ~p"/employees?sort=status&dir=desc")
    html = render(view)
    assert html =~ ~r/Alice Adams.*Bot Baker.*John Doe/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-status")

    # Click sort on type (asc: Agent -> Full-time Employee)
    view |> element("#employees-sort-type") |> render_click()
    assert_patched(view, ~p"/employees?sort=employee_type_label")
    html = render(view)
    assert html =~ ~r/Bot Baker.*Alice Adams/s
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-type")

    # Click sort on type again (desc: Full-time Employee -> Agent)
    view |> element("#employees-sort-type") |> render_click()
    assert_patched(view, ~p"/employees?sort=employee_type_label&dir=desc")
    html = render(view)
    assert html =~ ~r/Alice Adams.*Bot Baker/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-type")
  end

  test "paginates employee index with 25 rows per page and canonicalizes out of bounds page in address bar", %{
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
    assert has_element?(view, "#employees-pagination-summary", "Showing 1 to 25 of 27 results")
    assert has_element?(view, "#employees-pagination-previous[disabled]")
    assert has_element?(view, "#employees-pagination-page-1[aria-current='page']")

    # Navigate to page 2
    view |> element("#employees-pagination-next") |> render_click()
    assert_patched(view, ~p"/employees?page=2")

    assert has_element?(view, "#employees-pagination-summary", "Showing 26 to 27 of 27 results")
    assert has_element?(view, "#employees-pagination-page-2[aria-current='page']")
    assert has_element?(view, "#employees-pagination-next[disabled]")

    # Navigate to out-of-bounds page 999: automatically canonicalizes and patches URL to page 2
    {:ok, oob_view, _html} = conn |> log_in_as() |> live(~p"/employees?page=999")
    assert_patched(oob_view, ~p"/employees?page=2")
    assert has_element?(oob_view, "#employees-pagination-summary", "Showing 26 to 27 of 27 results")

    # Changing page size to 50 shows all 27 on page 1 and patches URL
    view
    |> form("#employees-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert_patched(view, ~p"/employees?per_page=50")
    assert has_element?(view, "#employees-pagination-summary", "Showing 1 to 27 of 27 results")

    # Invalid per_page falls back to 25
    {:ok, invalid_view, _html} = conn |> log_in_as() |> live(~p"/employees?per_page=11")
    assert has_element?(invalid_view, "#employees-pagination-summary", "Showing 1 to 25 of 27 results")
  end

  test "deletes an employee when authorized and clamps page if page becomes empty", %{
    conn: conn,
    scope: scope
  } do
    for i <- 2..26 do
      num = String.pad_leading("#{i}", 3, "0")

      {:ok, _emp} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-#{num}",
          full_name: "Person #{num}"
        })
    end

    {:ok, to_delete} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-027",
        full_name: "Temp Worker"
      })

    grant_capabilities!(["admin.employee.list", "admin.employee.delete"])

    # Visit page 2 where Temp Worker is the only employee (item 27 of 27)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees?page=2")

    assert has_element?(view, "#employee-#{to_delete.id}-delete")
    assert has_element?(view, "#employees-pagination-summary", "Showing 26 to 27 of 27 results")

    view |> element("#employee-#{to_delete.id}-delete") |> render_click()

    assert render(view) =~ "Employee deleted successfully."
    refute has_element?(view, "#employees td", "Temp Worker")

    # Because page 2 is now empty (total 26 employees on 25-per-page), it automatically clamped and patched to page 1
    assert_patched(view, ~p"/employees")
    assert has_element?(view, "#employees-pagination-summary", "Showing 1 to 25 of 26 results")
  end

  test "renders show page with standard edit button", %{conn: conn, employee: employee} do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "h1", "John Doe")
    assert has_element?(view, "#employee-edit")
  end
end
