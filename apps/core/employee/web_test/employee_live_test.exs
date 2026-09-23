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

  test "reaches the employee type list through a link carrying the demoted treatment", %{
    conn: conn
  } do
    grant_capabilities!(["admin.employee.list", "admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    assert has_element?(
             view,
             "a#employee-types[href='/employee-types'][title='Manage employee types']",
             "Employee Types"
           )

    assert has_element?(view, "#employee-types .hero-cog-6-tooth")

    # A navigating <.button> renders an anchor too, so the tag proves
    # nothing; the treatment is what demotion changed.
    assert has_element?(view, "a#employee-types.text-link")
    refute has_element?(view, "a#employee-types.border")
    refute has_element?(view, "a#employee-types.bg-action")
    refute has_element?(view, "a#employee-types.shadow-sm")
  end

  test "puts the primary action before the demoted link, as /companies does", %{conn: conn} do
    grant_capabilities!([
      "admin.employee.list",
      "admin.employee.create",
      "admin.employee-type.list"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    header = view |> element("main header") |> render()

    assert {primary, _} = :binary.match(header, ~s(id="employee-new"))
    assert {demoted, _} = :binary.match(header, ~s(id="employee-types"))
    assert primary < demoted
  end

  test "hides the employee type link from an actor who may not list types", %{conn: conn} do
    grant_capabilities!("admin.employee.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    refute has_element?(view, "#employee-types")
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

  test "the list's Edit action opens the employee's read-first record page", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.list", "admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    # The action keeps its capability gate and its glyph; it leads to the
    # record page, where every fact edits in place, not to a separate form.
    assert has_element?(view, "a#employee-#{employee.id}-edit[href='/employees/#{employee.id}']")
    refute has_element?(view, "a[href$='/edit']")

    {:ok, show, _html} =
      view
      |> element("#employee-#{employee.id}-edit")
      |> render_click()
      |> follow_redirect(conn |> log_in_as(), ~p"/employees/#{employee.id}")

    assert has_element?(show, "#employee-full-name[phx-hook='InlineEdit']")
  end

  test "hides the Edit action from an actor who may not update employees", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.list", "admin.employee.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees")

    refute has_element?(view, "#employee-#{employee.id}-edit")
  end

  test "renders show page header with the pin and no edit button", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "h1", "John Doe")
    # The facts edit in place, so an "Edit employee" button would be YAGNI.
    refute has_element?(view, "#employee-edit")
    refute has_element?(view, "main header button:not(#employee-pin)")

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

    test "the subordinates head renders the role pair the contrast gate measures", %{
      conn: conn,
      employee: employee
    } do
      grant_capabilities!("admin.employee.view")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # `theme_contrast_test.exs` gates `ink-subtle` against `surface-sunken`
      # because that is the pair the shared `<.table>` head renders, and this
      # section renders that head rather than a hand-written one (parity
      # finding C2).
      head_classes =
        view |> element("#subordinates-card thead") |> render() |> opening_tag_classes()

      cell_classes =
        view
        |> element("#subordinates-card thead th:first-child")
        |> render()
        |> opening_tag_classes()

      assert "bg-surface-sunken" in head_classes
      assert "text-ink-subtle" in cell_classes
    end

    test "supports inline editing of employee text fields", %{
      conn: conn,
      scope: scope,
      employee: employee
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      render_hook(view, "save_field", %{
        "id" => to_string(employee.id),
        "designation" => "Principal Architect"
      })

      assert has_element?(view, "#employee-designation-status[role='status']", "Saved")
      refute has_element?(view, "#flash-group", "updated")
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

      assert has_element?(view, "#employee-status-status[role='status']", "Saved")
      {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
      assert updated.status == "probation"

      # A successful save folds the field back to its read state.
      refute has_element?(view, "#employee-status-form")

      # Change employee type to part_time
      view |> element("#employee-employee_type-display") |> render_click()

      view
      |> form("#employee-type-form")
      |> render_change(%{"employee_type" => "part_time"})

      assert has_element?(view, "#employee-employee-type-status[role='status']", "Saved")
      refute has_element?(view, "#employee-status-status")
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

      assert has_element?(view, "#employee-department-status[role='status']", "Saved")
      {:ok, updated} = Employee.get_employee(scope, 73, employee.id)
      assert updated.department_id == 101

      # Assign supervisor
      view |> element("#employee-supervisor-display") |> render_click()

      view
      |> form("#employee-supervisor-form")
      |> render_change(%{"supervisor_id" => to_string(peer.id)})

      assert has_element?(view, "#employee-supervisor-status[role='status']", "Saved")
      assert has_element?(view, "#employee-view-supervisor", "Peer Pete")
      refute has_element?(view, "#employee-department-status")
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
      view |> element("#subordinates-table-sort-status") |> render_click()

      assert has_element?(
               view,
               "#subordinates-card th[aria-sort='ascending'] #subordinates-table-sort-status"
             )

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
      subordinate: subordinate,
      address: address
    } do
      grant_capabilities!(["admin.employee.view", "admin.employee.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

      # A page flash raised before the dialog opens would sit unreadable behind
      # the inert page, so opening the dialog dismisses it. The facts report in
      # place now, so the subordinate assignment supplies the flash.
      view |> element("#btn-toggle-add-subordinate") |> render_click()

      view
      |> form("#add-subordinate-form")
      |> render_submit(%{"subordinate_id" => to_string(subordinate.id)})

      assert has_element?(view, "#flash-info", "Subordinate assigned.")

      # Open modal
      view |> element("#btn-open-attach-address") |> render_click()
      assert_modal_dialog(view, "attach-address-modal", "Attach Address")
      refute has_element?(view, "#flash-info")

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

      # Priority commits in place through the shared editor — driven through
      # the field itself so the hook event reaches the discovered panel
      # component, as the browser hook's push would.
      view
      |> element("#address-priority-#{address.id}[phx-hook='InlineEdit']")
      |> render_hook("save_address_priority", %{
        "id" => to_string(address.id),
        "priority" => "10"
      })

      assert render(view) =~ "Address setting updated."
      assert has_element?(view, "#address-row-#{address.id}", "10")

      # Edit kinds — the read state is the trigger, addressed to the component
      view
      |> element("button#edit-kinds-#{address.id}")
      |> render_click()

      view
      |> element("input[phx-click='toggle_edit_kind'][phx-value-kind='billing']")
      |> render_click()

      view
      |> element("#save-kinds-#{address.id}")
      |> render_click(%{"address_id" => to_string(address.id)})

      assert render(view) =~ "Address kinds updated."

      # Sort addresses by priority through the shared table's header button
      view |> element("#addresses-table-sort-priority") |> render_click()
      assert has_element?(view, "th[aria-sort='ascending'] #addresses-table-sort-priority")

      # Detach address, confirmed through the shared dialog
      view |> element("#unlink-address-#{address.id}") |> render_click()
      assert_modal_dialog(view, "unlink-address-confirm", "will be unlinked from this employee.")
      view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()
      assert render(view) =~ "Address unlinked."
      refute has_element?(view, "#address-row-#{address.id}")
      assert has_element?(view, "#addresses-panel-notice", "Address unlinked.")
      assert has_element?(view, ~s(#addresses-panel-notice[role="status"]))

      view |> element("#btn-open-attach-address") |> render_click()
      assert_modal_dialog(view, "attach-address-modal", "Attach Address")
      refute has_element?(view, "#addresses-panel-notice")

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

  defp opening_tag_classes(html) do
    [opening_tag, _] = String.split(html, ">", parts: 2)
    [_, class_attribute] = Regex.run(~r/class="([^"]*)"/, opening_tag)

    String.split(class_attribute, ~r/\s+/, trim: true)
  end
end
