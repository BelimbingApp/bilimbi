defmodule BilimbiWeb.EmployeeShowFactsTest do
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

    %{scope: scope, employee: employee}
  end

  test "edits an agent job description with the shared long-text fact", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, _employee} =
             Employee.update_employee(scope, 73, employee.id, %{
               employee_type: "agent",
               job_description: "Supports the service desk."
             })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "#employee-job-description[phx-hook='InlineLongText']")
    assert has_element?(view, "#employee-job-description-display", "Supports the service desk.")

    view |> element("#employee-job-description-display") |> render_click()
    assert has_element?(view, "#employee-job-description-input[rows='2']")
    assert has_element?(view, "#employee-job-description-input[phx-mounted]")

    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "job_description" => "Supports the regional teams.\nCoordinates on-call work."
    })

    assert has_element?(view, "#employee-job-description-display", "Coordinates on-call work.")
    assert has_element?(view, "#employee-job-description-status[role='status']", "Saved")

    assert {:ok, %{job_description: "Supports the regional teams.\nCoordinates on-call work."}} =
             Employee.get_employee(scope, 73, employee.id)
  end

  test "saves each committed text fact in place and reports the outcome on that fact", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])
    {:ok, scope} = Tenancy.scope(41)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Every text fact is an in-place editor; there is no edit mode, no save
    # button and no edit button. The required columns refuse an emptied
    # input at the hook; the nullable ones commit it.
    for id <- ~w(employee-full-name employee-number) do
      assert has_element?(view, "##{id}[phx-hook='InlineEdit'][data-save-event='save_field']")
      refute has_element?(view, "##{id}[data-allow-empty]")
    end

    for id <- ~w(employee-short-name employee-designation employee-email employee-mobile-number) do
      assert has_element?(
               view,
               "##{id}[phx-hook='InlineEdit'][data-save-event='save_field'][data-allow-empty]"
             )
    end

    # The job description is an agent's fact only.
    refute has_element?(view, "#employee-job-description")
    refute has_element?(view, "#employee-edit")

    # A committed edit saves by itself; the title follows and nothing flashes.
    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "full_name" => "  Jane Doe  "
    })

    assert has_element?(view, "h1", "Jane Doe")
    assert has_element?(view, "#employee-view-full-name", "Jane Doe")
    assert has_element?(view, "#employee-full-name-status[role='status']", "Saved")
    assert page_title(view) == "Jane Doe"
    refute has_element?(view, "#flash-group", "updated")
    assert {:ok, %{full_name: "Jane Doe"}} = Employee.get_employee(scope, 73, employee.id)

    # "Saved" belongs to the most recent commit only, and clearing a nullable
    # fact is a real edit.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "email" => ""})

    assert has_element?(view, "#employee-email-status[role='status']", "Saved")
    refute has_element?(view, "#employee-full-name-status")
    assert has_element?(view, "#employee-email [data-role='text']", "—")
    assert {:ok, %{email: nil}} = Employee.get_employee(scope, 73, employee.id)

    # The employee number keeps Belimbing's id and its monospace treatment.
    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "employee_number" => "EMP-100"
    })

    assert has_element?(view, "#employee-view-employee-number", "EMP-100")
    assert has_element?(view, "#employee-number.font-mono")
    assert has_element?(view, "#employee-number-status[role='status']", "Saved")

    # A field the page does not edit as text is ignored, not written.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "status" => "terminated"})
    assert {:ok, %{status: "active"}} = Employee.get_employee(scope, 73, employee.id)
  end

  test "a refused commit keeps the stored value on screen and reports the reason on the fact", %{
    conn: conn,
    employee: employee
  } do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _peer} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-002", full_name: "Peer Pete"})

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    render_hook(view, "save_field", %{"id" => to_string(employee.id), "email" => "not-an-email"})

    assert has_element?(view, "#employee-email-status[role='alert']", "was not saved")
    assert has_element?(view, "#employee-email-status", "\"not-an-email\"")
    assert has_element?(view, "#employee-email-status", "Email has invalid format")
    assert has_element?(view, "#employee-view-email", "john@example.test")
    assert has_element?(view, "#employee-email input[aria-invalid='true']")
    refute has_element?(view, "#employee-email-status", "Saved")
    refute has_element?(view, "#flash-group", "was not saved")
    refute has_element?(view, "#flash-group", "Failed")
    assert {:ok, %{email: "john@example.test"}} = Employee.get_employee(scope, 73, employee.id)

    # The alert stays until that fact is committed again; a success elsewhere
    # does not clear it.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "designation" => "Lead"})
    assert has_element?(view, "#employee-email-status[role='alert']")
    assert has_element?(view, "#employee-designation-status", "Saved")

    # A required fact refuses an emptied value, and a taken employee number
    # is refused by the unique constraint, each with its own reason.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "full_name" => "   "})

    assert has_element?(
             view,
             "#employee-full-name-status[role='alert']",
             "Full Name can't be blank"
           )

    assert has_element?(view, "h1", "John Doe")
    refute has_element?(view, "#employee-designation-status")

    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "employee_number" => "EMP-002"
    })

    assert has_element?(
             view,
             "#employee-number-status[role='alert']",
             "Employee Number has already been taken"
           )

    assert {:ok, %{employee_number: "EMP-001", full_name: "John Doe"}} =
             Employee.get_employee(scope, 73, employee.id)

    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "email" => "jane@example.test"
    })

    refute has_element?(view, "#employee-email-status[role='alert']")
    assert has_element?(view, "#employee-email-status", "Saved")
    assert has_element?(view, "#employee-view-email", "jane@example.test")
  end

  test "a choice fact commits on change and a refused choice reports on that fact", %{
    conn: conn,
    employee: employee
  } do
    {:ok, scope} = Tenancy.scope(41)
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # The read state is the trigger; the select exists only after the click,
    # commits on change, and folds back to the read state with its outcome.
    assert has_element?(view, "#employee-status-display")
    refute has_element?(view, "#employee-status-form")

    view |> element("#employee-status-display") |> render_click()
    view |> form("#employee-status-form") |> render_change(%{"status" => "probation"})

    refute has_element?(view, "#employee-status-form")
    assert has_element?(view, "#employee-view-status", "Probation")
    assert has_element?(view, "#employee-status-status[role='status']", "Saved")

    assert has_element?(
             view,
             "#employee-status-display[aria-describedby='employee-status-status']"
           )

    refute has_element?(view, "#flash-group", "updated")
    assert {:ok, %{status: "probation"}} = Employee.get_employee(scope, 73, employee.id)

    # Escape or leaving the select cancels without writing.
    view |> element("#employee-supervisor-display") |> render_click()
    assert has_element?(view, "#employee-supervisor-form")
    render_hook(view, "cancel_edit_field", %{})
    refute has_element?(view, "#employee-supervisor-form")

    # A forged choice the select never offered is refused on its fact,
    # naming what was chosen; the stored value stays, and the refusal on one
    # fact does not clear the other's.
    render_hook(view, "save_status", %{"status" => "retired"})

    assert has_element?(
             view,
             "#employee-status-status[role='alert']",
             "\"retired\" was not saved: Status is invalid"
           )

    assert has_element?(view, "#employee-view-status", "Probation")

    render_hook(view, "save_supervisor", %{"supervisor_id" => "999999"})

    assert has_element?(
             view,
             "#employee-supervisor-status[role='alert']",
             "\"999999\" was not saved: Supervisor does not belong to the company"
           )

    assert has_element?(view, "#employee-status-status[role='alert']")

    assert {:ok, %{status: "probation", supervisor_id: nil}} =
             Employee.get_employee(scope, 73, employee.id)
  end

  test "refuses to change the platform orchestrator's identity on the fact", %{conn: conn} do
    CompanyFixtures.assign_primary_company!(41, 73)
    {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])
    {:ok, scope} = Tenancy.scope(41)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{orchestrator.id}")

    render_hook(view, "save_field", %{
      "id" => to_string(orchestrator.id),
      "employee_number" => "SYS-002"
    })

    assert has_element?(
             view,
             "#employee-number-status[role='alert']",
             "Employee Number cannot change the platform orchestrator identity"
           )

    assert has_element?(view, "#employee-view-employee-number", "SYS-001")
    refute has_element?(view, "#flash-group", "orchestrator")

    render_hook(view, "save_employee_type", %{"employee_type" => "full_time"})

    assert has_element?(
             view,
             "#employee-employee-type-status[role='alert']",
             "platform orchestrator"
           )

    assert {:ok, %{employee_number: "SYS-001", employee_type: "agent"}} =
             Employee.get_employee(scope, 73, orchestrator.id)
  end
end
