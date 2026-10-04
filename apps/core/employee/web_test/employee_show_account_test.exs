defmodule BilimbiWeb.EmployeeShowAccountTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

    %{scope: scope, employee: employee}
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
end
