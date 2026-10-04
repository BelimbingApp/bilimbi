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
    view |> element("#user-authz-confirm-confirm") |> render_click()
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
    view |> element("#user-authz-confirm-confirm") |> render_click()
    assert has_element?(view, "#flash-group", "denied")

    assert has_element?(
             view,
             "#denied-permissions-list dd#denied-domain-admin #denied-cap-badge-admin-company-view",
             "admin.company.view"
           )

    # Remove denial
    view |> element("#remove-denial-admin-company-view") |> render_click()
    view |> element("#user-authz-confirm-confirm") |> render_click()
    assert has_element?(view, "#flash-group", "The deny rule for admin.company.view was removed.")

    # Grant direct capability "admin.company.list"
    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.company.list"]})

    assert has_element?(view, "#flash-group", "Granted 1 capability.")
    assert has_element?(view, "#cap-badge-admin-company-list", "admin.company.list")

    # Remove direct capability grant
    view |> element("#remove-direct-cap-admin-company-list") |> render_click()
    view |> element("#user-authz-confirm-confirm") |> render_click()

    assert has_element?(
             view,
             "#flash-group",
             "The direct grant of admin.company.list was removed."
           )
  end

  # Every control on this card changes authorization for a real person, so
  # each one confirms through the shared dialog and names the role or
  # capability it is about -- a bare "Remove this role?" does not tell the
  # administrator which of several badges they are about to act on.
  test "confirms role removal and names the role and the user", %{conn: conn} do
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
    view |> element("#remove-role-#{assignment.id}") |> render_click()

    assert_modal_dialog(
      view,
      "user-authz-confirm",
      "The Editor role will be removed from Grace Hopper."
    )

    assert has_element?(view, "dialog#user-authz-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#user-authz-confirm-description",
             "They lose every capability this role grants unless another role or direct grant " <>
               "also provides it. The role can be assigned again."
           )

    # Cancelling keeps the role.
    view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#user-authz-confirm")
    assert has_element?(view, "#assigned-roles-list", "Editor")

    # A confirm with nothing held is a stale click and changes nothing.
    view |> with_target("#user-access-panel") |> render_click("remove_role", %{})
    assert has_element?(view, "#assigned-roles-list", "Editor")

    # Confirming removes it and reports the completed write as a success.
    view |> element("#remove-role-#{assignment.id}") |> render_click()

    assert has_element?(
             view,
             "#user-authz-confirm-confirm[phx-disable-with='Removing…']",
             "Remove"
           )

    view |> element("#user-authz-confirm-confirm") |> render_click()
    refute has_element?(view, "#user-authz-confirm")
    assert has_element?(view, "#flash-success", "The Editor role was removed.")
    refute has_element?(view, "#assigned-roles-list", "Editor")
  end

  test "confirms every capability control and names the capability and the user", %{conn: conn} do
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

    # Denying a role-derived capability revokes it, so it confirms first, with
    # the verb the dialog's danger action carries.
    refute has_element?(view, "#deny-cap-admin-company-view[data-confirm]")
    view |> element("#deny-cap-admin-company-view") |> render_click()

    assert_modal_dialog(
      view,
      "user-authz-confirm",
      "admin.company.view will be denied for Grace Hopper."
    )

    assert has_element?(
             view,
             "#user-authz-confirm-description",
             "The deny rule overrides every role that grants it and takes effect at once. " <>
               "It can be removed again from the denied list."
           )

    # Cancelling changes nothing.
    view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#user-authz-confirm")
    refute has_element?(view, "#denied-cap-badge-admin-company-view")

    view |> element("#deny-cap-admin-company-view") |> render_click()

    assert has_element?(
             view,
             "#user-authz-confirm-confirm[phx-disable-with='Denying…']",
             "Deny"
           )

    view |> element("#user-authz-confirm-confirm") |> render_click()
    refute has_element?(view, "#user-authz-confirm")
    assert has_element?(view, "#flash-success", "admin.company.view is denied for Grace Hopper.")
    assert has_element?(view, "#denied-cap-badge-admin-company-view")

    # Removing the deny rule restores access rather than revoking it, so the
    # copy says that instead of borrowing the revocation wording.
    refute has_element?(view, "#remove-denial-admin-company-view[data-confirm]")
    view |> element("#remove-denial-admin-company-view") |> render_click()

    assert_modal_dialog(
      view,
      "user-authz-confirm",
      "The deny rule for admin.company.view will be removed."
    )

    assert has_element?(
             view,
             "#user-authz-confirm-description",
             "Grace Hopper regains this capability from any role or direct grant that provides it."
           )

    view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
    assert has_element?(view, "#denied-cap-badge-admin-company-view")

    view |> element("#remove-denial-admin-company-view") |> render_click()
    view |> element("#user-authz-confirm-confirm", "Remove") |> render_click()

    assert has_element?(
             view,
             "#flash-success",
             "The deny rule for admin.company.view was removed."
           )

    refute has_element?(view, "#denied-cap-badge-admin-company-view")

    view
    |> form("#add-capabilities-form")
    |> render_submit(%{"capability_keys" => ["admin.company.list"]})

    # Removing a direct grant says what still keeps the capability in place.
    refute has_element?(view, "#remove-direct-cap-admin-company-list[data-confirm]")
    view |> element("#remove-direct-cap-admin-company-list") |> render_click()

    assert_modal_dialog(
      view,
      "user-authz-confirm",
      "The direct grant of admin.company.list will be removed from Grace Hopper."
    )

    assert has_element?(
             view,
             "#user-authz-confirm-description",
             "They keep this capability only if an assigned role still grants it. " <>
               "The grant can be added again."
           )

    view |> element("#user-authz-confirm-cancel", "Cancel") |> render_click()
    assert has_element?(view, "#cap-badge-admin-company-list")

    view |> element("#remove-direct-cap-admin-company-list") |> render_click()
    view |> element("#user-authz-confirm-confirm", "Remove") |> render_click()

    assert has_element?(
             view,
             "#flash-success",
             "The direct grant of admin.company.list was removed."
           )

    refute has_element?(view, "#cap-badge-admin-company-list")
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
