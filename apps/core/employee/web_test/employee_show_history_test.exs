defmodule BilimbiWeb.EmployeeShowHistoryTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
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

  test "an in-place edit appears in the record history without a remount", %{
    conn: conn,
    employee: employee
  } do
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
end
