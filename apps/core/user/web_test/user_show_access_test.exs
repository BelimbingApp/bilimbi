defmodule BilimbiWeb.UserShowAccessTest do
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

    assert has_element?(view, "#user-roles-heading + span", "1")
    assert has_element?(view, "#assigned-roles-list", "Editor")

    # Remove role
    assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 92)
    [assignment] = assignments.entries

    view |> element("#remove-role-#{assignment.id}") |> render_click()
    assert has_element?(view, "#user-roles-heading + span", "0")
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

    grant_capabilities!(["admin.user.view", "admin.user.update", "admin.company.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle effective permissions disclosure: each domain is a row of the
    # shared list, its capabilities the value.
    view |> element("#toggle-permissions-btn") |> render_click()

    assert has_element?(
             view,
             "#effective-permissions-list dd#permissions-domain-admin #cap-badge-admin-company-view"
           )

    # Deny role-derived capability
    view |> element("#deny-cap-admin-company-view") |> render_click()
    assert has_element?(view, "#flash-group", "denied")

    assert has_element?(
             view,
             "#denied-permissions-list dd#denied-domain-admin #denied-cap-badge-admin-company-view",
             "admin.company.view"
           )

    # Remove denial
    view |> element("#remove-denial-admin-company-view") |> render_click()
    assert has_element?(view, "#flash-group", "The deny rule for admin.company.view was removed.")

    # Grant direct capability "admin.company.list"
    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.company.list"]})

    assert has_element?(view, "#flash-group", "Granted 1 capability.")
    assert has_element?(view, "#cap-badge-admin-company-list", "admin.company.list")

    # Remove direct capability grant
    view |> element("#remove-direct-cap-admin-company-list") |> render_click()

    assert has_element?(
             view,
             "#flash-group",
             "The direct grant of admin.company.list was removed."
           )
  end

  # A change the administrator can undo from the same card commits on click:
  # a removed role is assigned again from the picker, a removed grant added
  # again, a deny rule lifted from the denied list. No dialog stands in the
  # way, and the outcome names the role and the person.
  test "removes another user's role on click, without a dialog", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, role} = Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Editor", code: "editor"})

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

    assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 92)
    [assignment] = assignments.entries

    refute has_element?(view, "#remove-role-#{assignment.id}[data-confirm]")

    # A confirm with nothing held is a stale click and changes nothing.
    view |> with_target("#user-access-panel") |> render_click("remove_role", %{})
    assert has_element?(view, "#assigned-roles-list", "Editor")

    view |> element("#remove-role-#{assignment.id}") |> render_click()

    refute has_element?(view, "#user-authz-confirm")
    assert has_element?(view, "#flash-success", "The Editor role was removed.")
    refute has_element?(view, "#assigned-roles-list", "Editor")
    assert Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 92).entries == []

    # The way back is the picker, which offers the role again.
    view |> element("#toggle-assign-roles-btn") |> render_click()
    assert has_element?(view, "#assign-roles-form", "Editor")
  end

  test "changes another user's capability rules on click, without a dialog", %{conn: conn} do
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

    grant_capabilities!(["admin.user.view", "admin.user.update", "admin.company.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    view |> element("#toggle-permissions-btn") |> render_click()

    # Denying a role-derived capability is lifted again from the denied list.
    refute has_element?(view, "#deny-cap-admin-company-view[data-confirm]")
    view |> element("#deny-cap-admin-company-view") |> render_click()
    refute has_element?(view, "#user-authz-confirm")
    assert has_element?(view, "#flash-success", "admin.company.view is denied for Grace Hopper.")
    assert has_element?(view, "#denied-cap-badge-admin-company-view")

    refute has_element?(view, "#remove-denial-admin-company-view[data-confirm]")
    view |> element("#remove-denial-admin-company-view") |> render_click()
    refute has_element?(view, "#user-authz-confirm")

    assert has_element?(
             view,
             "#flash-success",
             "The deny rule for admin.company.view was removed."
           )

    refute has_element?(view, "#denied-cap-badge-admin-company-view")

    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.company.list"]})

    refute has_element?(view, "#remove-direct-cap-admin-company-list[data-confirm]")
    view |> element("#remove-direct-cap-admin-company-list") |> render_click()
    refute has_element?(view, "#user-authz-confirm")

    assert has_element?(
             view,
             "#flash-success",
             "The direct grant of admin.company.list was removed."
           )

    refute has_element?(view, "#cap-badge-admin-company-list")

    # The way back: the picker offers the capability again.
    assert has_element?(view, "#add-capabilities-form", "admin.company.list")
  end

  # The pickers only offer what the acting user holds, so a change to one's
  # own account may not be one they can take back. Every change there
  # confirms first; the same change to another user commits on click.
  describe "the acting user's own account" do
    setup do
      {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

      {:ok, editor} =
        Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Editor", code: "editor"})

      {:ok, _} =
        Bilimbi.Base.Authz.replace_role_capabilities(scope, editor.id, ["admin.company.view"])

      UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Kiat Ng"})
      {:ok, _} = Bilimbi.Base.Authz.assign_role(scope, 73, :user, 91, editor.id)
      grant_capabilities!(["admin.user.view", "admin.user.update", "admin.company.list"])

      assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 91).entries
      editor_assignment = Enum.find(assignments, &(&1.role_id == editor.id))

      %{scope: scope, editor: editor_assignment}
    end

    test "confirms removing a role", %{conn: conn, scope: scope, editor: editor} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

      view |> element("#remove-role-#{editor.id}") |> render_click()

      assert_modal_dialog(
        view,
        "user-authz-confirm",
        "The Editor role will be removed from your account."
      )

      assert has_element?(view, "dialog#user-authz-confirm[role='alertdialog']")
      assert has_element?(view, "#user-authz-confirm-description", "your own access")

      # Cancelling keeps the role.
      view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#user-authz-confirm")
      assert has_element?(view, "#assigned-roles-list", "Editor")

      view |> element("#remove-role-#{editor.id}") |> render_click()

      assert has_element?(
               view,
               "#user-authz-confirm-confirm[phx-disable-with='Removing…']",
               "Remove"
             )

      view |> element("#user-authz-confirm-confirm") |> render_click()
      refute has_element?(view, "#user-authz-confirm")
      assert has_element?(view, "#flash-success", "The Editor role was removed.")
      refute has_element?(view, "#assigned-roles-list", "Editor")

      assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 91).entries
      refute Enum.any?(assignments, &(&1.id == editor.id))
    end

    test "confirms removing a direct grant", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

      view |> element("#toggle-permissions-btn") |> render_click()
      view |> element("#remove-direct-cap-admin-company-list") |> render_click()

      assert_modal_dialog(
        view,
        "user-authz-confirm",
        "The direct grant of admin.company.list will be removed from your account."
      )

      assert has_element?(view, "#user-authz-confirm-description", "your own access")

      view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
      assert has_element?(view, "#cap-badge-admin-company-list")

      view |> element("#remove-direct-cap-admin-company-list") |> render_click()
      view |> element("#user-authz-confirm-confirm", "Remove") |> render_click()
      refute has_element?(view, "#user-authz-confirm")

      assert has_element?(
               view,
               "#flash-success",
               "The direct grant of admin.company.list was removed."
             )

      refute has_element?(view, "#cap-badge-admin-company-list")
    end

    test "confirms denying a capability and lifting the deny rule", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

      view |> element("#toggle-permissions-btn") |> render_click()
      view |> element("#deny-cap-admin-company-view") |> render_click()

      assert_modal_dialog(
        view,
        "user-authz-confirm",
        "admin.company.view will be denied for your account."
      )

      assert has_element?(view, "#user-authz-confirm-description", "your own access")

      view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#denied-cap-badge-admin-company-view")

      view |> element("#deny-cap-admin-company-view") |> render_click()
      view |> element("#user-authz-confirm-confirm", "Deny") |> render_click()
      assert has_element?(view, "#flash-success", "admin.company.view is denied for Kiat Ng.")
      assert has_element?(view, "#denied-cap-badge-admin-company-view")

      view |> element("#remove-denial-admin-company-view") |> render_click()

      assert_modal_dialog(
        view,
        "user-authz-confirm",
        "The deny rule for admin.company.view will be removed from your account."
      )

      view |> element("#user-authz-confirm-confirm", "Remove") |> render_click()
      refute has_element?(view, "#user-authz-confirm")
      refute has_element?(view, "#denied-cap-badge-admin-company-view")
    end
  end

  test "prevents privilege escalation when assigning roles not held by the administrator", %{
    conn: conn
  } do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, privileged_role} =
      Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Executive", code: "executive"})

    {:ok, _} =
      Bilimbi.Base.Authz.replace_role_capabilities(scope, privileged_role.id, [
        "admin.company.create",
        "admin.company.delete"
      ])

    {:ok, basic_role} =
      Bilimbi.Base.Authz.create_role(scope, 73, %{name: "Auditor", code: "auditor"})

    {:ok, _} =
      Bilimbi.Base.Authz.replace_role_capabilities(scope, basic_role.id, ["admin.user.view"])

    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    # Administrator only holds admin.user.view and admin.user.update
    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle assign roles panel
    view |> element("#toggle-assign-roles-btn") |> render_click()

    # Basic role (Auditor with admin.user.view) is grantable because actor holds its capabilities
    assert has_element?(view, "#assign-roles-form", "Auditor")

    # Privileged role (Executive with admin.company.create/delete) is hidden from available roles
    refute has_element?(view, "#assign-roles-form", "Executive")

    # Attempt forged assignment of the privileged role
    view
    |> form("#assign-roles-form")
    |> render_submit(%{"role_ids" => ["#{privileged_role.id}"]})

    assert has_element?(view, "#flash-group", "You cannot grant roles you do not hold.")

    # Target user did not receive the privileged role
    assignments = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, 92)
    assert assignments.entries == []
  end

  test "prevents privilege escalation when granting direct capabilities not held by the administrator",
       %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    # Administrator only holds admin.user.view and admin.user.update
    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # Toggle permissions disclosure
    view |> element("#toggle-permissions-btn") |> render_click()

    # Capabilities not held by the actor should not appear in the available capabilities picker
    refute has_element?(view, "#add-capabilities-form", "admin.system.database-table.edit")
    refute has_element?(view, "#add-capabilities-form", "admin.company.delete")

    # Attempt forged grant of an unheld capability
    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.system.database-table.edit"]})

    assert has_element?(view, "#flash-group", "You cannot grant capabilities you do not hold.")

    # Asserted at the database, not just on the flash. The refusal message is
    # cosmetic: a handler that writes and *then* flashes the error passes every
    # assertion above. The sibling role test already checks the store this way.
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    granted =
      Bilimbi.Base.Authz.list_principal_capabilities(scope,
        principal_type: :user,
        principal_id: 92
      )

    refute Enum.any?(granted.entries, &(&1.capability == "admin.system.database-table.edit"))
  end
end
