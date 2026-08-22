defmodule BilimbiWeb.EmployeeShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
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

  test "shows record history when the actor can list audit logs", %{
    conn: conn,
    employee: employee
  } do
    AuditFixtures.create_audit_tables!()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: "Bilimbi.Core.Employee.Schema",
        auditable_id: to_string(employee.id),
        subject_name: "John Doe",
        event: "updated",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{"designation" => "Analyst"},
        new_values: %{"designation" => "Lead Analyst"}
      })

    grant_capabilities!(["admin.employee.view", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    assert has_element?(view, "#employee-record-history-toggle", "History")
    assert has_element?(view, "#employee-record-history-panel", "Analyst")
    assert has_element?(view, "#employee-record-history-panel", "Lead Analyst")
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

    assert has_element?(view, "#account-panel-notice", "User link updated.")

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

    assert has_element?(view, "#account-panel-notice", "Failed to update linked user account.")

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

    grant =
      Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.employee.update"))

    assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

    render_submit(view, "save_field", %{"full_name" => "Forged Name"})

    assert has_element?(view, "#flash-group", "You do not have permission to edit employees.")
    assert {:ok, %{full_name: "John Doe"}} = Employee.get_employee(scope, 73, employee.id)
  end
end
