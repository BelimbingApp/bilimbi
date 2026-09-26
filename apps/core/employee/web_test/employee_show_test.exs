defmodule BilimbiWeb.EmployeeShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
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

    assert has_element?(
             view,
             "a#employee-back[href='/employees'][title='Back to employees']",
             "Back"
           )

    refute has_element?(view, "button#employee-back")
    refute has_element?(view, "main header button:not(#employee-pin)")
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

    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "job_description" => "Supports the regional teams.\nCoordinates on-call work."
    })

    assert has_element?(view, "#employee-job-description-display", "Coordinates on-call work.")
    assert has_element?(view, "#employee-job-description-status[role='status']", "Saved")

    assert {:ok, %{job_description: "Supports the regional teams.\nCoordinates on-call work."}} =
             Employee.get_employee(scope, 73, employee.id)
  end

  test "presents the facts as the shared list and the subordinates as the shared table", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # One heading treatment: every section is a named region whose title is
    # the shared level-two heading, and none writes its own h3, dl or table.
    for id <- ~w(employee-details employment-info) do
      assert has_element?(
               view,
               "##{id}-card[role='region'][aria-labelledby='#{id}-heading'] h2##{id}-heading"
             )

      refute has_element?(view, "##{id}-card h3")
    end

    assert has_element?(
             view,
             "#subordinates-card[role='region'][aria-labelledby='employee-subordinates-heading'] h2#employee-subordinates-heading",
             "Subordinates"
           )

    refute has_element?(view, "#subordinates-card h3")

    # The facts are rows of one definition list; every value cell keeps its id
    # and hosts the in-place editor at full width.
    assert has_element?(view, "#employee-details-card dl dd#employee-view-full-name", "John Doe")

    assert has_element?(
             view,
             "dd#employee-view-full-name #employee-full-name[phx-hook='InlineEdit']"
           )

    assert has_element?(view, "#employee-details-card dl dt", "Employee Number")
    assert has_element?(view, "dd#employee-view-employee-number", "EMP-001")
    refute has_element?(view, "dd#employee-view-job-description")

    assert has_element?(view, "#employment-info-card dl dd#employee-view-company")
    assert has_element?(view, "dd#employee-view-department #employee-department-display")
    assert has_element?(view, "dd#employee-view-status .rounded-full", "Active")
    assert has_element?(view, "dd#employee-view-employment-start")

    # The linked account is a row of the same list, its value the Core User
    # embed with its choice, under the label this page gives the fact.
    assert has_element?(view, "#employment-info-card dl dt", "User")
    assert has_element?(view, "dd#employee-view-user #account-panel form#employee-user-form")
    assert has_element?(view, "#employee-user option[value='91']", "Ada Lovelace")

    # The subordinates are the shared table: caption, sortable heads with a
    # truthful sort state, the empty row saying what is missing, and the
    # section's own action in its heading row.
    assert has_element?(view, "#subordinates-card caption", "Subordinates")
    assert has_element?(view, "#employee-subordinates-heading + span", "0")

    assert has_element?(
             view,
             "#subordinates-card th[aria-sort='ascending'] button#subordinates-table-sort-full_name"
           )

    assert has_element?(view, "#subordinates-table-empty", "No subordinates")
    assert has_element?(view, "#subordinates-table-empty", "appear here")
    assert has_element?(view, "#subordinates-card #btn-toggle-add-subordinate", "Add")

    {:ok, scope} = Tenancy.scope(41)

    {:ok, report} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-002",
        full_name: "Sam Report",
        email: "sam@example.test"
      })

    view |> element("#btn-toggle-add-subordinate") |> render_click()

    view
    |> form("#add-subordinate-form")
    |> render_submit(%{"subordinate_id" => to_string(report.id)})

    assert has_element?(view, "tbody#subordinates-table tr#subordinate-row-#{report.id}")

    assert has_element?(
             view,
             "#subordinate-link-#{report.id}[href='/employees/#{report.id}']",
             "Sam Report"
           )

    assert has_element?(view, "#employee-subordinates-heading + span", "1")

    # Sorting stays with the page, through the shared sort buttons.
    view |> element("#subordinates-table-sort-status") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #subordinates-table-sort-status")

    # Removing is a demoted icon action that confirms through the shared
    # dialog, never natively.
    assert has_element?(
             view,
             "button#remove-subordinate-#{report.id}[aria-label='Remove Sam Report as subordinate'] .hero-x-mark"
           )

    refute has_element?(view, "#remove-subordinate-#{report.id}[data-confirm]")
    refute has_element?(view, "#remove-subordinate-#{report.id}", "Remove")

    view |> element("#remove-subordinate-#{report.id}") |> render_click()

    assert_modal_dialog(
      view,
      "remove-subordinate-confirm",
      "Sam Report will no longer report to #{employee.full_name}."
    )

    assert has_element?(view, "dialog#remove-subordinate-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#remove-subordinate-confirm-description",
             "Both employee records are kept. The reporting line can be set again."
           )

    # Cancelling keeps the reporting line.
    view |> element("#remove-subordinate-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#remove-subordinate-confirm")
    assert has_element?(view, "#subordinate-link-#{report.id}")

    # Confirming removes it and reports the completed write as a success.
    view |> element("#remove-subordinate-#{report.id}") |> render_click()

    assert has_element?(
             view,
             "#remove-subordinate-confirm-confirm[phx-disable-with='Removing…']",
             "Remove"
           )

    view |> element("#remove-subordinate-confirm-confirm") |> render_click()
    refute has_element?(view, "#remove-subordinate-confirm")
    assert has_element?(view, "#flash-success", "Sam Report no longer reports to")
    refute has_element?(view, "#subordinate-link-#{report.id}")
  end

  test "an agent has no linked-account row", %{conn: conn} do
    CompanyFixtures.assign_primary_company!(41, 73)
    {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{orchestrator.id}")

    assert has_element?(view, "dd#employee-view-employee-type", "Agent")
    assert has_element?(view, "dd#employee-view-job-description")
    refute has_element?(view, "dd#employee-view-user")
    refute has_element?(view, "#account-panel")
  end

  test "a viewer without admin.employee.update sees the facts with no editors", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!("admin.employee.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Every fact reads as plain text: no inline editors, no choice triggers,
    # no select forms, and the header holds no button beyond the pin.
    assert has_element?(view, "#employee-view-full-name", "John Doe")
    assert has_element?(view, "#employee-view-employee-number", "EMP-001")
    assert has_element?(view, "#employee-view-email", "john@example.test")
    assert has_element?(view, "#employee-view-short-name", "—")
    assert has_element?(view, "#employee-view-status", "Active")
    assert has_element?(view, "#employee-view-department", "None")
    assert has_element?(view, "#employee-view-company", "Bilimbi Industries")

    refute has_element?(view, "#employee-details-card [phx-hook='InlineEdit']")
    refute has_element?(view, "#employment-info-card [phx-hook='InlineEdit']")

    for field <- ~w(department supervisor employee_type status) do
      refute has_element?(view, "#employee-#{field}-display")
    end

    refute has_element?(view, "#employee-status-form")
    refute has_element?(view, "#employee-edit")
    refute has_element?(view, "main header button:not(#employee-pin)")

    # A forged commit from a viewer writes nothing and reports the refusal.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "full_name" => "Forged"})
    assert has_element?(view, "#flash-group", "You do not have permission to edit employees.")
    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{full_name: "John Doe"}} = Employee.get_employee(scope, 73, employee.id)
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

  test "an in-place edit appears in the record history without a remount", %{
    conn: conn,
    employee: employee
  } do
    AuditFixtures.create_audit_tables!()
    grant_capabilities!(["admin.employee.view", "admin.employee.update", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
    view |> element("#employee-record-history-toggle") |> render_click()
    assert has_element?(view, "#employee-record-history-empty")

    render_hook(view, "save_field", %{"id" => to_string(employee.id), "full_name" => "Jane Doe"})
    assert has_element?(view, "h1", "Jane Doe")

    refute has_element?(view, "#employee-record-history-empty")
    assert has_element?(view, "#employee-record-history-panel", "Updated")
    assert has_element?(view, "#employee-record-history-panel", "John Doe")
    assert has_element?(view, "#employee-record-history-panel", "Jane Doe")
  end

  test "shows record history and impersonation attribution when the actor can list audit logs", %{
    conn: conn,
    employee: employee
  } do
    AuditFixtures.create_audit_tables!()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, impersonated} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 92,
        impersonator_id: 91,
        auditable_type: Employee.addressable_identity(),
        auditable_id: to_string(employee.id),
        subject_name: "John Doe",
        event: "updated",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{"designation" => "Analyst"},
        new_values: %{"designation" => "Lead Analyst"}
      })

    {:ok, ordinary} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: Employee.addressable_identity(),
        auditable_id: to_string(employee.id),
        subject_name: "John Doe",
        event: "updated",
        occurred_at: ~N[2026-08-18 09:59:00],
        old_values: %{"email" => "old@example.test"},
        new_values: %{"email" => "john@example.test"}
      })

    grant_capabilities!(["admin.employee.view", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(
             view,
             "button#employee-record-history-toggle[aria-expanded='false']",
             "History"
           )

    view |> element("#employee-record-history-toggle") |> render_click()
    assert has_element?(view, "#employee-record-history-panel", "Analyst")
    assert has_element?(view, "#employee-record-history-panel", "Lead Analyst")

    assert has_element?(
             view,
             "#employee-record-history-entry-#{impersonated.id}",
             "User #92 · impersonated by User #91"
           )

    refute has_element?(
             view,
             "#employee-record-history-entry-#{ordinary.id}",
             "impersonated by"
           )
  end

  test "the addresses panel is the shared table with in-place priority and a demoted unlink", %{
    conn: conn,
    employee: employee
  } do
    AddressFixtures.create_geonames_tables!()
    AddressFixtures.create_address_tables!()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, home} =
      Address.create_address(scope, %{label: "Home", line1: "12 Jalan Damai", locality: "Ipoh"})

    {:ok, :attached} =
      Address.attach_to_employee(scope, home.id, employee.id, %{kind: ["other"], priority: 1})

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Shared heading with its count over the shared table; no hand-written table.
    assert has_element?(view, "#addresses-panel h2#employee-addresses-heading", "Addresses")
    assert has_element?(view, "#employee-addresses-heading + span", "1")
    assert has_element?(view, "#addresses-panel caption", "Employee addresses")

    assert has_element?(
             view,
             "#addresses-panel th[aria-sort='ascending'] button#addresses-table-sort-label"
           )

    assert has_element?(view, "tbody#addresses-table tr#address-row-#{home.id}")
    assert has_element?(view, "#address-link-#{home.id}[href='/addresses/#{home.id}']", "Home")
    assert has_element?(view, "#address-row-#{home.id}", "12 Jalan Damai, Ipoh")

    # Sorting reaches the panel, not the page.
    view |> element("#addresses-table-sort-priority") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #addresses-table-sort-priority")

    # Priority commits in place through the shared editor addressed to the panel.
    assert has_element?(
             view,
             "#address-priority-#{home.id}[phx-hook='InlineEdit'][data-save-event='save_address_priority']"
           )

    view
    |> element("#address-priority-#{home.id}")
    |> render_hook("save_address_priority", %{"id" => to_string(home.id), "priority" => "4"})

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='success']",
             "Address setting updated."
           )

    assert has_element?(view, "#address-priority-#{home.id} [data-role='text']", "4")

    {:ok, [attached]} = Address.list_employee_attached_addresses(scope, employee.id)
    assert attached.priority == 4

    # Unlinking is a demoted icon action confirmed through the shared dialog,
    # which leads with the consequence; the empty state then says what to do.
    assert has_element?(
             view,
             "button#unlink-address-#{home.id}[aria-label='Unlink address'] .hero-link-slash"
           )

    refute has_element?(view, "#unlink-address-#{home.id}[data-confirm]")

    view |> element("#unlink-address-#{home.id}") |> render_click()

    assert_modal_dialog(
      view,
      "unlink-address-confirm",
      "“Home” will be unlinked from this employee."
    )

    assert has_element?(
             view,
             "#unlink-address-confirm-description",
             "The address itself is kept and can be attached again."
           )

    view |> element("#unlink-address-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#unlink-address-confirm")
    assert has_element?(view, "#address-row-#{home.id}")

    view |> element("#unlink-address-#{home.id}") |> render_click()
    view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

    refute has_element?(view, "#unlink-address-confirm")
    refute has_element?(view, "#address-row-#{home.id}")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='success']",
             "Address unlinked."
           )

    assert {:ok, _home} = Address.get_address(scope, home.id)
    assert has_element?(view, "#addresses-table-empty", "No addresses linked.")

    assert has_element?(
             view,
             "#addresses-table-empty",
             "Attach one of the company's addresses to this employee."
           )
  end

  test "unlinking an address whose link is already gone informs rather than refuses", %{
    conn: conn,
    employee: employee
  } do
    AddressFixtures.create_geonames_tables!()
    AddressFixtures.create_address_tables!()
    {:ok, scope} = Tenancy.scope(41)
    {:ok, home} = Address.create_address(scope, %{label: "Home", line1: "12 Jalan Damai"})
    {:ok, flat} = Address.create_address(scope, %{label: "Flat", line1: "4 Jalan Seri"})
    {:ok, :attached} = Address.attach_to_employee(scope, home.id, employee.id)
    {:ok, :attached} = Address.attach_to_employee(scope, flat.id, employee.id)

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Another operator unlinks the address while this list still shows it:
    # the confirmation runs against a link that is already gone.
    :ok = Address.detach_from_employee(scope, home.id, employee.id)
    view |> element("#unlink-address-#{home.id}") |> render_click()
    view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

    refute has_element?(view, "#unlink-address-confirm")
    refute has_element?(view, "#address-row-#{home.id}")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='info']",
             "That address is no longer linked."
           )

    # A request naming an address the refreshed list no longer holds.
    view |> element("#unlink-address-#{flat.id}") |> render_click(%{"id" => "#{home.id}"})

    refute has_element?(view, "#unlink-address-confirm")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='info']",
             "That address is no longer linked."
           )
  end

  test "hides the destructive action without admin.employee.delete", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    refute has_element?(view, "#employee-delete")
    refute has_element?(view, "#employee-edit")
    assert has_element?(view, "#employee-full-name[phx-hook='InlineEdit']")
  end

  test "deletes an ordinary employee", %{conn: conn, employee: employee} do
    grant_capabilities!([
      "admin.employee.list",
      "admin.employee.view",
      "admin.employee.delete"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Deleting confirms through the shared dialog, which names the employee
    # and says what cannot be undone; no native confirm remains.
    refute has_element?(view, "#employee-delete[data-confirm]")
    view |> element("#employee-delete") |> render_click()

    assert_modal_dialog(view, "delete-employee-confirm", "John Doe will be deleted.")
    assert has_element?(view, "dialog#delete-employee-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#delete-employee-confirm-description",
             "The employment record is removed and the person no longer appears in the directory. This cannot be undone."
           )

    # Cancelling keeps the employee on their page.
    view |> element("#delete-employee-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#delete-employee-confirm")
    assert has_element?(view, "#employee-delete")

    # Confirming deletes and leaves for the directory.
    view |> element("#employee-delete") |> render_click()

    assert has_element?(
             view,
             "#delete-employee-confirm-confirm[phx-disable-with='Deleting…']",
             "Delete"
           )

    view |> element("#delete-employee-confirm-confirm") |> render_click()

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

    # The refusal is met after confirming: the dialog closes and the flash
    # says why nothing was deleted.
    view |> element("#employee-delete") |> render_click()
    view |> element("#delete-employee-confirm-confirm") |> render_click()

    refute has_element?(view, "#delete-employee-confirm")
    assert has_element?(view, "#flash-error", "the platform orchestrator cannot be deleted.")
    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, _} = Employee.get_employee(scope, 73, orchestrator.id)
  end

  # The account panel is a `core/user`-owned discovered embed (#581); these
  # page-level tests stay here because the page is where the seam composes.
  # The link path had no coverage at all, and it was where #409 lived: a
  # `rescue _ -> {:ok, nil}` around the write meant every failure flashed
  # success. These assert the store, because the rendered outcome was the
  # thing that lied.
  test "links a user account and records it in the database", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    view
    |> element("#employee-user-form")
    |> render_change(%{"user_id" => "91"})

    assert has_element?(
             view,
             "#account-panel-notice[role='status'][data-kind='success']",
             "User link updated."
           )

    # The notice is dismissed in place, like every panel notice.
    view |> element("#account-panel-notice-dismiss") |> render_click()
    refute has_element?(view, "#account-panel-notice")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{employee_id: linked}} = User.get_user(scope, 73, 91)
    assert linked == employee.id
  end

  # The manifest-dispatched Core User coordinator commits the unlink and the
  # employee type transition together; there is no post-update panel notice to
  # mistake for a successful reconciliation (#581).
  test "switching the employee type to agent unlinks the account", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    view
    |> element("#employee-user-form")
    |> render_change(%{"user_id" => "91"})

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{employee_id: _linked}} = User.get_user(scope, 73, 91)

    view |> element("#employee-employee_type-display") |> render_click()

    view
    |> element("#employee-type-form")
    |> render_change(%{"employee_type" => "agent"})

    assert {:ok, %{employee_type: "agent"}} = Employee.get_employee(scope, 73, employee.id)
    assert {:ok, %{employee_id: nil}} = User.get_user(scope, 73, 91)
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

    assert has_element?(
             view,
             "#account-panel-notice[role='alert'][data-kind='error']",
             "Failed to update linked user account."
           )

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{employee_id: nil}} = User.get_user(scope, 74, 92)
  end

  test "a write forged after grant revocation changes nothing", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    {:ok, scope} = Tenancy.scope(41)

    # A commit that did land, so the refusal below has a stale "Saved" to clear.
    render_hook(view, "save_field", %{"id" => to_string(employee.id), "designation" => "Lead"})
    assert has_element?(view, "#employee-designation-status[role='status']", "Saved")

    grant =
      Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.employee.update"))

    assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

    render_hook(view, "save_field", %{
      "id" => to_string(employee.id),
      "full_name" => "Forged Name"
    })

    assert has_element?(view, "#flash-group", "You do not have permission to edit employees.")

    # The refusal is the whole outcome: no "Saved" from the earlier commit
    # stands beside it, and the choice facts are refused the same way.
    refute has_element?(view, "#employee-designation-status")

    render_hook(view, "save_status", %{"status" => "terminated"})
    render_hook(view, "save_department", %{"department_id" => "101"})

    assert {:ok, %{full_name: "John Doe", status: "active", department_id: nil}} =
             Employee.get_employee(scope, 73, employee.id)
  end

  test "a viewer without admin.employee.update keeps an agent job description's line breaks",
       %{conn: conn, employee: employee} do
    grant_capabilities!("admin.employee.view")
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, _employee} =
             Employee.update_employee(scope, 73, employee.id, %{
               employee_type: "agent",
               job_description: "Supports the regional teams.\nCoordinates on-call work."
             })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    refute has_element?(view, "#employee-job-description-display")
    refute has_element?(view, "#employee-job-description-input")

    assert has_element?(
             view,
             "#employee-job-description .whitespace-pre-wrap",
             "Coordinates on-call work."
           )
  end
end
