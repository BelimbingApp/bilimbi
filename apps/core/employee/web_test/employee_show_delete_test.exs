defmodule BilimbiWeb.EmployeeShowDeleteTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz.LiveAuthorization
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

  test "refuses deletion when permission is revoked after mount", %{
    conn: conn,
    scope: scope,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
    assert has_element?(view, "#employee-delete")

    revoke_capability!(scope, "admin.employee.delete")

    view |> element("#employee-delete") |> render_click()

    assert has_element?(view, "#flash-error", LiveAuthorization.denied_message())
    refute has_element?(view, "#delete-employee-confirm")
    refute has_element?(view, "#employee-delete")
    assert {:ok, _} = Employee.get_employee(scope, 73, employee.id)
  end

  test "refuses deletion when permission is revoked after opening confirmation", %{
    conn: conn,
    scope: scope,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.view", "admin.employee.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
    view |> element("#employee-delete") |> render_click()
    assert has_element?(view, "#delete-employee-confirm-confirm")

    revoke_capability!(scope, "admin.employee.delete")

    view |> element("#delete-employee-confirm-confirm") |> render_click()

    assert has_element?(view, "#flash-error", LiveAuthorization.denied_message())
    refute has_element?(view, "#flash-success")
    refute has_element?(view, "#employee-delete")
    assert {:ok, _} = Employee.get_employee(scope, 73, employee.id)
  end
end
