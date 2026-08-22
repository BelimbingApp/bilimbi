defmodule BilimbiWeb.EmployeeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    AddressFixtures.create_address_tables!()
    GeonamesFixtures.insert_country!()
    GeonamesFixtures.insert_admin1!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Acme Corp", code: "acme"})
    CompanyFixtures.assign_primary_company!(41, 73)

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Admin User",
      email: "admin@example.test"
    })

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        designation: "Software Engineer",
        email: "john@example.test",
        status: "active",
        employee_type: "full_time"
      })

    %{scope: scope, employee: employee}
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employees")
  end

  test "redirects away when the actor lacks admin.employee.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employees")
  end

  test "renders employee index for authorized actors and highlights the navigation", %{
    conn: conn,
    scope: scope
  } do
    grant_capabilities!("admin.employee.list")

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Other Co",
      code: "other"
    })

    {:ok, _grace} =
      Employee.create_employee(scope, 74, %{
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

  test "renders the Department column from Company's public API", %{conn: conn, scope: scope} do
    grant_capabilities!("admin.employee.list")

    {:ok, dept_type} =
      Bilimbi.Core.Company.create_department_type(%{
        code: "engineering",
        name: "Engineering",
        category: "operational"
      })

    CompanyFixtures.insert_department!(101, 73, dept_type.id)

    {:ok, _assigned} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-777",
        full_name: "Dept Member",
        department_id: 101
      })

    {:ok, view, html} = conn |> log_in_as() |> live(~p"/employees")

    assert html =~ "Department"
    assert has_element?(view, "#employees td", "Engineering")
    # John Doe has no department; his cell renders the muted dash.
    assert has_element?(view, "#employees td span", "—")
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

  test "sorts employees by name, type, and status with aria-sort, url patch, and verified row ordering",
       %{
         conn: conn,
         scope: scope
       } do
    {:ok, _alice} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-002",
        full_name: "Alice Adams",
        status: "terminated",
        employee_type: "full_time"
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
    assert_patched(view, ~p"/employees?dir=desc&sort=status")
    html = render(view)
    assert html =~ ~r/Alice Adams.*Bot Baker.*John Doe/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-status")

    # Click sort on type (asc: Agent -> Full Time)
    view |> element("#employees-sort-type") |> render_click()
    assert_patched(view, ~p"/employees?sort=employee_type_label")
    html = render(view)
    assert html =~ ~r/Bot Baker.*Alice Adams/s
    assert has_element?(view, "th[aria-sort='ascending'] #employees-sort-type")

    # Click sort on type again (desc: Full Time -> Agent)
    view |> element("#employees-sort-type") |> render_click()
    assert_patched(view, ~p"/employees?dir=desc&sort=employee_type_label")
    html = render(view)
    assert html =~ ~r/Alice Adams.*Bot Baker/s
    assert has_element?(view, "th[aria-sort='descending'] #employees-sort-type")
  end

  test "paginates employee index with 25 rows per page and canonicalizes out of bounds page in address bar",
       %{
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

    # Navigate to out-of-bounds page 999: automatically canonicalizes and live redirects to page 2
    assert {:error, {:live_redirect, %{to: "/employees?page=2"}}} =
             conn |> log_in_as() |> live(~p"/employees?page=999")

    # Changing page size to 50 shows all 27 on page 1 and patches URL
    view
    |> form("#employees-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert_patched(view, ~p"/employees?per_page=50")
    assert has_element?(view, "#employees-pagination-summary", "Showing 1 to 27 of 27 results")

    # Invalid per_page falls back to 25
    {:ok, invalid_view, _html} = conn |> log_in_as() |> live(~p"/employees?per_page=11")

    assert has_element?(
             invalid_view,
             "#employees-pagination-summary",
             "Showing 1 to 25 of 27 results"
           )
  end

  test "deletes an employee when authorized and clamps page if page becomes empty", %{
    conn: conn,
    scope: scope
  } do
    for i <- 2..25 do
      num = String.pad_leading("#{i}", 3, "0")

      {:ok, _emp} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-#{num}",
          full_name: "Person #{num}"
        })
    end

    {:ok, to_delete} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-026",
        full_name: "Temp Worker"
      })

    grant_capabilities!(["admin.employee.list", "admin.employee.delete"])

    # Visit page 2 where Temp Worker is the only employee (item 26 of 26)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees?page=2")

    assert has_element?(view, "#employee-#{to_delete.id}-delete")
    assert has_element?(view, "#employees-pagination-summary", "Showing 26 to 26 of 26 results")

    view |> element("#employee-#{to_delete.id}-delete") |> render_click()

    assert render(view) =~ "Employee deleted successfully."
    refute has_element?(view, "#employees td", "Temp Worker")

    # Because page 2 is now empty (total 25 employees on 25-per-page), it automatically clamped and patched to page 1
    assert_patched(view, ~p"/employees")
    assert has_element?(view, "#employees-pagination-summary", "Showing 1 to 25 of 25 results")
  end

  test "refuses delete event when actor lacks admin.employee.delete capability", %{
    conn: conn,
    scope: scope,
    employee: employee
  } do
    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    refute has_element?(view, "#employee-#{employee.id}-delete")

    assert render_click(view, "delete", %{"id" => to_string(employee.id)}) =~
             "You do not have permission to delete employees."

    assert {:ok, _found} = Employee.get_employee(scope, 73, employee.id)
  end

  test "renders show page with standard edit button", %{conn: conn, employee: employee} do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "h1", "John Doe")
    assert has_element?(view, "#employee-edit")

    assert has_element?(
             view,
             "#employee-pin[data-nav-pin-record='true'][data-nav-pin-label='Administration / Employees / John Doe'][data-nav-pin-url='/employees/#{employee.id}']"
           )
  end

  describe "employee show page parity with Belimbing" do
    setup %{scope: scope} do
      CompanyFixtures.insert_department!(101, 73)

      {:ok, subordinate} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-002",
          full_name: "Subordinate Sam",
          designation: "Junior Dev",
          status: "probation"
        })

      {:ok, peer} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-003",
          full_name: "Peer Pete",
          designation: "Staff Dev",
          status: "active"
        })

      {:ok, address} =
        Address.create_address(scope, %{
          label: "Office Address",
          line1: "123 Tech Park",
          locality: "Cyberjaya",
          postcode: "63000",
          country_iso: "MY"
        })

      %{subordinate: subordinate, peer: peer, address: address}
    end

    test "renders full details page with all sections and cards", %{
      conn: conn,
      employee: employee
    } do
      grant_capabilities!([
        "admin.employee.view",
        "admin.employee.update",
        "admin.employee.delete"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      assert has_element?(view, "#employee-details-card")
      assert has_element?(view, "#employment-info-card")
      assert has_element?(view, "#subordinates-card")
      assert has_element?(view, "#addresses-card")
      assert has_element?(view, "#employee-danger")

      assert has_element?(view, "#employee-full-name", "John Doe")
      assert has_element?(view, "#employee-number", "EMP-001")
      assert has_element?(view, "#employee-designation", "Software Engineer")
      assert has_element?(view, "#employee-email", "john@example.test")
    end

    test "supports inline editing of employee text fields", %{
      conn: conn,
      scope: scope,
      employee: employee
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      render_hook(view, "save_field", %{
        "field" => "designation",
        "value" => "Principal Architect"
      })

      assert render(view) =~ "Designation updated successfully."
      assert has_element?(view, "#employee-designation", "Principal Architect")

      {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
      assert updated.designation == "Principal Architect"
    end

    test "updates employee status and employee type via selects", %{
      conn: conn,
      scope: scope,
      employee: employee
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # The selects sit behind edit-in-place read states (#619): the badge
      # shows first, and the form exists only after the trigger is clicked.
      assert has_element?(view, "#employee-status-display")
      refute has_element?(view, "#employee-status-form")

      view |> element("#employee-status-display") |> render_click()

      view
      |> form("#employee-status-form")
      |> render_change(%{"status" => "probation"})

      assert render(view) =~ "Status updated."
      {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
      assert updated.status == "probation"

      # A successful save folds the field back to its read state.
      refute has_element?(view, "#employee-status-form")

      # Change employee type to part_time
      view |> element("#employee-employee_type-display") |> render_click()

      view
      |> form("#employee-type-form")
      |> render_change(%{"employee_type" => "part_time"})

      assert render(view) =~ "Employee type updated."
      {:ok, updated2} = Employee.get_employee(scope, 73, employee.id)
      assert updated2.employee_type == "part_time"
    end

    test "updates department and supervisor assignments", %{
      conn: conn,
      scope: scope,
      employee: employee,
      peer: peer
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # Assign department (open the edit-in-place field first, #619)
      view |> element("#employee-department-display") |> render_click()

      view
      |> form("#employee-department-form")
      |> render_change(%{"department_id" => "101"})

      assert render(view) =~ "Department assignment saved."
      {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
      assert updated.department_id == 101

      # Assign supervisor
      view |> element("#employee-supervisor-display") |> render_click()

      view
      |> form("#employee-supervisor-form")
      |> render_change(%{"supervisor_id" => to_string(peer.id)})

      assert render(view) =~ "Supervisor assignment saved."
      {:ok, updated2} = Employee.get_employee(scope, 73, employee.id)
      assert updated2.supervisor_id == peer.id
    end

    test "links and unlinks user account", %{
      conn: conn,
      employee: employee
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # Link user 91 to this employee
      view
      |> form("#employee-user-form")
      |> render_change(%{"user_id" => "91"})

      assert render(view) =~ "User link updated."

      # Unlink user
      view
      |> form("#employee-user-form")
      |> render_change(%{"user_id" => ""})

      assert render(view) =~ "User link updated."
    end

    test "manages direct subordinates with add, sort, and remove", %{
      conn: conn,
      scope: scope,
      employee: employee,
      subordinate: subordinate
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # Toggle add subordinate form
      view |> element("#btn-toggle-add-subordinate") |> render_click()
      assert has_element?(view, "#add-subordinate-form")

      # Assign subordinate
      view
      |> form("#add-subordinate-form")
      |> render_submit(%{"subordinate_id" => to_string(subordinate.id)})

      assert render(view) =~ "Subordinate assigned."
      assert has_element?(view, "#subordinate-row-#{subordinate.id}", "Subordinate Sam")

      # Verify in domain
      {:ok, subs} = Employee.list_subordinates(scope, 73, employee.id)
      assert length(subs) == 1

      # Sort subordinates by status
      view
      |> element("button[phx-click='sort_subordinates'][phx-value-sort_by='status']")
      |> render_click()

      assert has_element?(view, "#subordinates-table")

      # Remove subordinate
      view
      |> element("#remove-subordinate-#{subordinate.id}")
      |> render_click()

      assert render(view) =~ "Subordinate removed."
      refute has_element?(view, "#subordinate-row-#{subordinate.id}")

      {:ok, subs_after} = Employee.list_subordinates(scope, 73, employee.id)
      assert subs_after == []
    end

    test "manages address attachments, kinds, priority, primary toggle, and detach", %{
      conn: conn,
      scope: scope,
      employee: employee,
      address: address
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # Open modal
      view |> element("#btn-open-attach-address") |> render_click()
      assert has_element?(view, "#attach-address-modal")

      # Attach address with shipping kind and priority 5
      view
      |> form("#attach-address-modal-form")
      |> render_submit(%{
        "address" => %{
          "address_id" => to_string(address.id),
          "kinds" => ["shipping"],
          "is_primary" => "true",
          "priority" => "5"
        }
      })

      assert render(view) =~ "Address attached."
      refute has_element?(view, "#attach-address-modal")
      assert has_element?(view, "#address-row-#{address.id}")
      assert has_element?(view, "#address-row-#{address.id}", "Shipping")
      assert has_element?(view, "#address-row-#{address.id}", "5")

      # Toggle primary
      view |> element("#toggle-primary-#{address.id}") |> render_click()
      assert render(view) =~ "Address setting updated."

      # Edit priority — driven through the clickable element so the event
      # reaches the discovered panel component, as a user's click would.
      view
      |> element("div[phx-click='edit_address_priority'][phx-value-id='#{address.id}']")
      |> render_click()

      assert has_element?(view, "#priority-form-#{address.id}")

      view
      |> form("#priority-form-#{address.id}")
      |> render_submit(%{"address_id" => to_string(address.id), "priority" => "10"})

      assert render(view) =~ "Address setting updated."
      assert has_element?(view, "#address-row-#{address.id}", "10")

      # Edit kinds — element-driven for the same component-target reason
      view
      |> element("div[phx-click='edit_address_kinds'][phx-value-id='#{address.id}']")
      |> render_click()

      view
      |> element("input[phx-click='toggle_edit_kind'][phx-value-kind='billing']")
      |> render_click()

      view
      |> element("#save-kinds-#{address.id}")
      |> render_click(%{"address_id" => to_string(address.id)})

      assert render(view) =~ "Address kinds updated."

      # Sort addresses by priority
      view
      |> element("button[phx-click='sort_addresses'][phx-value-sort_by='priority']")
      |> render_click()

      # Detach address
      view |> element("#unlink-address-#{address.id}") |> render_click()
      assert render(view) =~ "Address unlinked."
      refute has_element?(view, "#address-row-#{address.id}")

      {:ok, attached} = Address.list_employee_attached_addresses(scope, employee.id)
      assert attached == []
    end

    test "deletes regular employee from details page and navigates back to list", %{
      conn: conn,
      scope: scope,
      subordinate: subordinate
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.delete"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{subordinate.id}")

      assert has_element?(view, "#employee-delete")

      view |> element("#employee-delete") |> render_click()

      assert_redirect(view, ~p"/employees")
      assert {:error, :employee_not_found} = Employee.get_employee(scope, 73, subordinate.id)
    end

    test "refuses deletion of platform orchestrator with flash error", %{
      conn: conn,
      scope: scope
    } do
      {:ok, orchestrator, _} = Employee.ensure_platform_orchestrator()
      grant_capabilities!(["admin.employee.view", "admin.employee.delete"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{orchestrator.id}")

      view |> element("#employee-delete") |> render_click()

      assert render(view) =~ "The platform orchestrator cannot be deleted."
      assert {:ok, _still_exists} = Employee.get_employee(scope, 73, orchestrator.id)
    end
  end
end
