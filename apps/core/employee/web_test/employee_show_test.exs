defmodule BilimbiWeb.EmployeeShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee

  setup do
    signed_in_identity!()
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

  test "inside a workspace tile the page announces the employee it shows", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!("admin.employee.view")
    token = Bilimbi.Base.UI.Workspace.host_token("phx-a-host")
    :ok = Bilimbi.Base.UI.Workspace.subscribe(Bilimbi.Base.UI.Workspace.topic(41, 91, token))

    {:ok, _view, _html} =
      conn
      |> log_in_as()
      |> put_req_header("sec-fetch-dest", "iframe")
      |> live(~p"/employees/#{employee.id}?ws=#{token}")

    assert_receive {:workspace_joined}
    assert_receive {:workspace_fact, %{kind: "core/employee", id: id}}
    assert id == employee.id
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
