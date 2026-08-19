defmodule BilimbiWeb.UserShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_external_access_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
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

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/91")
  end

  test "redirects away when the actor lacks admin.user.view", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/users/91")
  end

  test "shows the user with company link and verification state", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    assert has_element?(view, "h1", "Grace Hopper")
    assert has_element?(view, "#user-back[href='/users']", "Back")
    assert has_element?(view, "a[href='/companies/73']", "Bilimbi Industries")
    assert has_element?(view, "#app-content", "unverified")
    refute has_element?(view, "#user-edit")
    refute has_element?(view, "#user-danger")
  end

  test "hides the destructive action without admin.user.delete", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    refute has_element?(view, "#user-delete")
    assert has_element?(view, "#user-edit")
  end

  test "redirects to the index for a user outside the tenant", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 93,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    assert {:error, {:live_redirect, %{to: "/users"}}} =
             conn |> log_in_as() |> live(~p"/users/93")
  end

  test "deletes another user with admin.user.delete", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.list", "admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    view |> element("#user-delete") |> render_click()

    assert_redirected_with_flash(view, "/users")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users")
    refute has_element?(view, "#users td", "Grace Hopper")
  end

  test "shows a user whose company is archived, matching index visibility", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      code: "archived",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 76,
      name: "Ada Archived",
      email: "archived@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")

    assert has_element?(view, "h1", "Ada Archived")
    refute has_element?(view, "#app-content", "does not exist in this workspace")
  end

  test "refuses to delete a user whose company is archived", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      code: "archived",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 76,
      name: "Ada Archived",
      email: "archived@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")

    view |> element("#user-delete") |> render_click()

    assert has_element?(view, "#flash-group", "while their company is archived")
  end

  test "refuses to delete the signed-in account", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

    view |> element("#user-delete") |> render_click()

    assert has_element?(view, "#flash-group", "cannot delete your own account")
  end

  test "shows impersonate action when actor has admin.user.impersonate", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Admin"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Target",
      email: "target@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.impersonate"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    assert has_element?(view, "#user-impersonate[href='/admin/impersonate/92']", "Impersonate")

    # When viewing own profile, impersonate button is hidden
    {:ok, own_view, _html} = conn |> log_in_as() |> live(~p"/users/91")
    refute has_element?(own_view, "#user-impersonate")
  end

  test "updates user name and email via inline edit", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Update name
    render_hook(view, "save_field", %{"field" => "name", "value" => "Grace Brewster Hopper"})
    assert has_element?(view, "h1", "Grace Brewster Hopper")

    # Update email
    render_hook(view, "save_field", %{"field" => "email", "value" => "grace.hopper@example.com"})
    assert has_element?(view, "#app-content", "grace.hopper@example.com")

    # Invalid email format should show error flash
    render_hook(view, "save_field", %{"field" => "email", "value" => "invalid-email"})
    assert has_element?(view, "#flash-group", "Failed to update email")
  end

  test "reassigns company and unassigns to unaffiliated", %{conn: conn} do
    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Beta Industries",
      code: "beta"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])
    grant_capabilities!(["admin.user.view", "admin.user.update"], company_id: 75)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Reassign company to 75
    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "75"})

    assert has_element?(view, "#flash-group", "Company reassigned")

    # Clear company to unaffiliated
    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => ""})

    assert has_element?(view, "#flash-group", "unaffiliated")
    assert has_element?(view, "#app-content", "Unaffiliated")
  end

  test "assigns and removes roles", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, role} = Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Editor", code: "editor"})

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle assign roles panel
    view |> element("#toggle-assign-roles-btn") |> render_click()

    # Assign role
    view
    |> form("#assign-roles-form")
    |> render_submit(%{"role_ids" => ["#{role.id}"]})

    assert has_element?(view, "#assigned-roles-count", "1")
    assert has_element?(view, "#assigned-roles-list", "Editor")

    # Remove role
    assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 92)
    [assignment] = assignments.entries

    view |> element("#remove-role-#{assignment.id}") |> render_click()
    assert has_element?(view, "#assigned-roles-count", "0")
  end

  test "grants direct capability, denies role-derived capability, and removes grant", %{
    conn: conn
  } do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, role} = Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Auditor", code: "auditor"})

    {:ok, _} =
      Bilimbi.Base.Authz.replace_role_capabilities(scope, role.id, ["admin.company.view"])

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, _} = Bilimbi.Base.Authz.assign_role(scope, 73, :user, 92, role.id)

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle effective permissions disclosure
    view |> element("#toggle-permissions-btn") |> render_click()

    # Deny role-derived capability
    view |> element("#deny-cap-admin-company-view") |> render_click()
    assert has_element?(view, "#flash-group", "denied")
    assert has_element?(view, "#denied-cap-badge-admin-company-view", "admin.company.view")

    # Remove denial
    view |> element("#remove-denial-admin-company-view") |> render_click()
    assert has_element?(view, "#flash-group", "Capability rule removed.")

    # Grant direct capability "admin.company.list"
    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.company.list"]})

    assert has_element?(view, "#flash-group", "Granted 1 capability.")
    assert has_element?(view, "#cap-badge-admin-company-list", "admin.company.list")

    # Remove direct capability grant
    view |> element("#remove-direct-cap-admin-company-list") |> render_click()
    assert has_element?(view, "#flash-group", "Capability rule removed.")
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

    # Create an employee in company 73
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, emp} =
      Bilimbi.Core.Employee.create_employee(scope, 73, %{
        full_name: "Grace Hopper",
        employee_number: "EMP-001",
        designation: "Rear Admiral",
        status: "active"
      })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle link employee
    view |> element("#toggle-link-employee-btn") |> render_click()

    # Link existing employee
    view
    |> form("#link-employee-form")
    |> render_submit(%{"employee_id" => "#{emp.id}"})

    assert has_element?(view, "#flash-group", "Employee linked.")
    assert has_element?(view, "#employees-count", "1")
    assert has_element?(view, "#user-employees-table", "EMP-001")
    assert has_element?(view, "#user-employees-table", "Rear Admiral")

    # Unlink employee
    view |> element("#unlink-employee-#{emp.id}") |> render_click()
    assert has_element?(view, "#flash-group", "Employee unlinked.")
    assert has_element?(view, "#employees-count", "0")

    # Open add employee modal and create new employee
    view |> element("#open-add-employee-modal-btn") |> render_click()
    assert has_element?(view, "#add-employee-modal")

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
    assert has_element?(view, "#employees-count", "1")
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
    expires = NaiveDateTime.add(now, 86400, :second)

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

    assert has_element?(view, "#external-accesses-count", "1")
    assert has_element?(view, "#user-external-accesses-table", "portal.view")
    assert has_element?(view, "#user-external-accesses-table", "portal.orders")
    assert has_element?(view, "#user-external-accesses-table", "Valid")

    # Sort external accesses
    render_hook(view, "sort_external_accesses", %{"sort_by" => "access_status"})
    assert has_element?(view, "#user-external-accesses-table", "Valid")
  end

  defp assert_redirected_with_flash(view, to) do
    assert {path, _flash} = assert_redirect(view)
    assert path == to
  end
end
