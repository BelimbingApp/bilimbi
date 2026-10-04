defmodule BilimbiWeb.UserShowAccountTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_external_access_tables!()
    Bilimbi.Core.Employee.ensure_system_types()

    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    :ok
  end

  test "changes user password as administrator with confirmation validation", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle change password section
    view |> element("#toggle-change-password-btn") |> render_click()

    # Submit with mismatched password confirmation
    view
    |> form("#user-password-form")
    |> render_submit(%{"password" => "newpassword123", "password_confirmation" => "different123"})

    assert has_element?(view, "#flash-group", "Passwords do not match")

    # Submit with matching password
    view
    |> form("#user-password-form")
    |> render_submit(%{
      "password" => "newpassword123",
      "password_confirmation" => "newpassword123"
    })

    assert has_element?(view, "#flash-group", "Password updated successfully")
  end

  test "links and unlinks employee record, and creates employee from modal", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    # Create an employee in company 73 with department
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    CompanyFixtures.create_departments_table!()

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "INSERT INTO company_department_types (id, code, name, category, is_active) VALUES ($1, $2, $3, $4, true)",
      [1, "eng", "Engineering", "operations"]
    )

    CompanyFixtures.insert_department!(1, 73, 1)

    {:ok, emp} =
      Bilimbi.Core.Employee.create_employee(scope, 73, %{
        full_name: "Grace Hopper",
        employee_number: "EMP-001",
        designation: "Rear Admiral",
        status: "active",
        department_id: 1
      })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    assert has_element?(view, "#user-employees-table-sort-department", "Department")

    # Toggle link employee
    view |> element("#toggle-link-employee-btn") |> render_click()

    # Link existing employee
    view
    |> form("#link-employee-form")
    |> render_submit(%{"employee_id" => "#{emp.id}"})

    assert has_element?(view, "#flash-group", "Employee linked.")
    assert has_element?(view, "#user-employees-heading + span", "1")
    assert has_element?(view, "#user-employees-table", "EMP-001")
    assert has_element?(view, "#user-employees-table", "Engineering")
    assert has_element?(view, "#user-employees-table", "Rear Admiral")

    # Sort employees by department
    render_hook(view, "sort_employees", %{"sort_by" => "department"})
    assert has_element?(view, "#user-employees-table", "Engineering")

    # Unlinking confirms through the shared dialog, which names the employee
    # record and says it is kept.
    refute has_element?(view, "#unlink-employee-#{emp.id}[data-confirm]")
    view |> element("#unlink-employee-#{emp.id}") |> render_click()

    assert_modal_dialog(view, "unlink-employee-confirm", "will be unlinked from")
    assert has_element?(view, "dialog#unlink-employee-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#unlink-employee-confirm-description",
             "The employee record is kept and can be linked again."
           )

    # Cancelling keeps the link.
    view |> element("#unlink-employee-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#unlink-employee-confirm")
    assert has_element?(view, "#user-employees-heading + span", "1")

    # Confirming unlinks and reports the completed write as a success.
    view |> element("#unlink-employee-#{emp.id}") |> render_click()

    assert has_element?(
             view,
             "#unlink-employee-confirm-confirm[phx-disable-with='Unlinking…']",
             "Unlink"
           )

    view |> element("#unlink-employee-confirm-confirm") |> render_click()
    refute has_element?(view, "#unlink-employee-confirm")
    assert has_element?(view, "#flash-success", "was unlinked from")
    assert has_element?(view, "#user-employees-heading + span", "0")

    # Open add employee modal and create new employee
    view |> element("#open-add-employee-modal-btn") |> render_click()
    assert_modal_dialog(view, "add-employee-modal", "Add Employee Record")

    view
    |> form("#modal-create-employee-form")
    |> render_submit(%{
      "employee" => %{
        "full_name" => "Grace Hopper New",
        "employee_number" => "EMP-002",
        "designation" => "Chief Engineer",
        "status" => "active"
      }
    })

    assert has_element?(view, "#flash-group", "created and linked")
    assert has_element?(view, "#user-employees-heading + span", "1")
    assert has_element?(view, "#user-employees-table", "EMP-002")
  end

  test "displays external accesses and allows sorting", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    # Insert relationship and external access in company 73
    CompanyFixtures.insert_relationship_type!(11)
    CompanyFixtures.insert_relationship!(1, 73, 73, 11)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    expires = NaiveDateTime.add(now, 86_400, :second)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      """
      INSERT INTO company_external_accesses (
        id, company_id, relationship_id, user_id, permissions, is_active, access_granted_at, access_expires_at, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5::json, $6, $7, $8, $9, $10)
      """,
      [
        1,
        73,
        1,
        92,
        Jason.encode!(["portal.view", "portal.orders"]),
        true,
        now,
        expires,
        now,
        now
      ]
    )

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    assert has_element?(view, "#user-external-accesses-heading + span", "1")
    assert has_element?(view, "#user-external-accesses-table", "portal.view")
    assert has_element?(view, "#user-external-accesses-table", "portal.orders")
    assert has_element?(view, "#user-external-accesses-table", "Valid")

    # Sort external accesses
    render_hook(view, "sort_external_accesses", %{"sort_by" => "access_status"})
    assert has_element?(view, "#user-external-accesses-table", "Valid")
  end

  test "a write forged after grant revocation changes nothing", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, emp} =
      Bilimbi.Core.Employee.create_employee(scope, 73, %{
        full_name: "Revocation Probe",
        employee_number: "EMP-609"
      })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

    grant =
      Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.user.update"))

    assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

    render_submit(view, "link_employee", %{"employee_id" => "#{emp.id}"})

    assert has_element?(view, "#flash-group", "You do not have permission to edit users.")
    assert {:ok, %{employee_id: nil}} = Bilimbi.Core.User.get_user(scope, 73, 91)
  end
end
