defmodule BilimbiWeb.UserShowPermissionsTest do
  @moduledoc """
  The Roles & Permissions section of the user page: the two pickers' searches
  narrow what they list, and a reader who finds no Roles control or no
  capability picker is told the real reason in a sentence they can act on,
  never left with a bare "No roles assigned.".
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @manage "admin.user.update"

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_external_access_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    Bilimbi.Core.Employee.ensure_system_types()

    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    # 91 is the signed-in administrator; 92 is the user whose page is open.
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    %{scope: scope}
  end

  defp insert_target!(attrs \\ %{}) do
    UserFixtures.insert_user!(
      Map.merge(
        %{id: 92, company_id: 73, name: "Grace Hopper", email: "grace@example.com"},
        attrs
      )
    )
  end

  defp create_role!(scope, name, code, capabilities) do
    {:ok, role} = Authz.create_role(scope, 73, %{name: name, code: code})
    {:ok, _} = Authz.replace_role_capabilities(scope, role.id, capabilities)
    role
  end

  defp open_page(conn) do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    view
  end

  defp open_effective_permissions(view) do
    view |> element("#toggle-permissions-btn") |> render_click()
    view
  end

  describe "capability search" do
    test "narrows the picker to matching keys and says when nothing matches", %{conn: conn} do
      insert_target!()
      grant_capabilities!(["admin.user.view", @manage])

      view = conn |> open_page() |> open_effective_permissions()

      # The picker offers what the administrator may grant: their own two keys.
      assert has_element?(view, "#available-cap-label-admin-user-view")
      assert has_element?(view, "#available-cap-label-admin-user-update")
      refute has_element?(view, "#available-capabilities-empty")

      # Typing narrows the list; the non-match is gone, not merely unchecked.
      view
      |> form("#capability-search-form", %{"value" => "update"})
      |> render_change()

      assert has_element?(view, "#available-cap-label-admin-user-update")
      refute has_element?(view, "#available-cap-label-admin-user-view")
      refute has_element?(view, "#available-capabilities-empty")

      # A search that matches nothing says so instead of going blank. Every
      # installed key begins with its domain, so "core" is the reported case.
      view
      |> form("#capability-search-form", %{"value" => "core"})
      |> render_change()

      refute has_element?(view, "#available-capabilities-list label")
      assert has_element?(view, "#available-capabilities-empty", "No capabilities match “core”")
      assert has_element?(view, "#available-capabilities-empty", "Clear the search")

      # Clearing restores the whole list.
      view
      |> form("#capability-search-form", %{"value" => ""})
      |> render_change()

      assert has_element?(view, "#available-cap-label-admin-user-view")
      assert has_element?(view, "#available-cap-label-admin-user-update")
      refute has_element?(view, "#available-capabilities-empty")
    end
  end

  describe "role search" do
    test "narrows the picker to matching names and says when nothing matches", %{
      conn: conn,
      scope: scope
    } do
      auditor = create_role!(scope, "Auditor", "auditor", ["admin.user.view"])
      editor = create_role!(scope, "Editor", "editor", [@manage])
      insert_target!()
      grant_capabilities!(["admin.user.view", @manage])

      view = open_page(conn)

      # A reader who may assign a role sees the control and no explanation.
      assert has_element?(view, "#toggle-assign-roles-btn", "Roles")
      refute has_element?(view, "#assign-roles-unavailable")

      view |> element("#toggle-assign-roles-btn") |> render_click()
      assert has_element?(view, "#available-role-label-#{auditor.id}", "Auditor")
      assert has_element?(view, "#available-role-label-#{editor.id}", "Editor")

      view
      |> form("#role-search-form", %{"value" => "aud"})
      |> render_change()

      assert has_element?(view, "#available-role-label-#{auditor.id}", "Auditor")
      refute has_element?(view, "#available-role-label-#{editor.id}")
      refute has_element?(view, "#available-roles-empty")

      view
      |> form("#role-search-form", %{"value" => "zzz"})
      |> render_change()

      refute has_element?(view, "#available-roles-list label")
      assert has_element?(view, "#available-roles-empty", "No roles match “zzz”")
      assert has_element?(view, "#available-roles-empty", "Clear the search")
    end
  end

  describe "why the Roles control is absent" do
    test "an administrator without #{@manage} is told the capability by name", %{
      conn: conn,
      scope: scope
    } do
      create_role!(scope, "Auditor", "auditor", ["admin.user.view"])
      insert_target!()
      grant_capabilities!(["admin.user.view"])

      view = conn |> open_page() |> open_effective_permissions()

      refute has_element?(view, "#toggle-assign-roles-btn")

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "You do not have permission to assign roles to this user, which needs admin.user.update."
             )

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Ask an operator to review your role."
             )

      # The capability picker states the same condition in its own place.
      refute has_element?(view, "#add-capabilities-section")

      assert has_element?(
               view,
               "#add-capabilities-unavailable",
               "You do not have permission to add capabilities to this user, which needs admin.user.update."
             )
    end

    # The fourth condition, a user without a company, has no sentence to
    # show because the page never mounts such an account: `get_tenant_user/2`
    # resolves a user through its company, so the page redirects instead.
    # This pins that fact so the branch's absence from the cases above is
    # deliberate rather than an oversight.
    test "a user without a company cannot be opened here at all", %{conn: conn, scope: scope} do
      create_role!(scope, "Auditor", "auditor", ["admin.user.view"])
      insert_target!(%{company_id: nil})
      grant_capabilities!(["admin.user.view", @manage])

      assert {:error, {:live_redirect, %{to: "/users"}}} =
               conn |> log_in_as() |> live(~p"/users/92")
    end

    test "with no roles in the workspace, the reader is told and sent to create one", %{
      conn: conn
    } do
      insert_target!()
      grant_capabilities!(["admin.user.view", @manage])

      # Without the capability to create a role, the sentence names it.
      view = open_page(conn)
      refute has_element?(view, "#toggle-assign-roles-btn")
      assert has_element?(view, "#assign-roles-unavailable", "No roles exist yet")

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Roles are created on the Roles page, which needs admin.authz.role.create; your account does not hold it."
             )

      refute has_element?(view, "#assign-roles-unavailable a")

      # Able to see the Roles page but not create there: a link to the page.
      grant_capabilities!(["admin.authz.role.list"])
      view = open_page(conn)
      assert has_element?(view, "#assign-roles-index-link[href='/authz/roles']", "Roles")
      refute has_element?(view, "#assign-roles-create-link")

      # Able to create: the link goes straight to the create page.
      grant_capabilities!(["admin.authz.role.create"])
      view = open_page(conn)

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Create one on the Roles page, then assign it here."
             )

      assert has_element?(
               view,
               "#assign-roles-create-link[href='/authz/roles/create']",
               "Create a role"
             )

      refute has_element?(view, "#assign-roles-index-link")
    end

    test "when the user already holds every role, the reader is told", %{
      conn: conn,
      scope: scope
    } do
      auditor = create_role!(scope, "Auditor", "auditor", ["admin.user.view"])
      insert_target!()
      {:ok, _} = Authz.assign_role(scope, 73, :user, 92, auditor.id)
      grant_capabilities!(["admin.user.view", @manage])

      view = open_page(conn)

      assert has_element?(view, "#assigned-roles-list", "Auditor")
      refute has_element?(view, "#toggle-assign-roles-btn")
      assert has_element?(view, "#assign-roles-unavailable", "No roles left to assign")

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "This user already holds every role that exists in this workspace."
             )
    end

    test "when no remaining role is one the administrator may grant, the guard is explained",
         %{conn: conn, scope: scope} do
      create_role!(scope, "Executive", "executive", ["admin.company.create"])
      insert_target!()
      grant_capabilities!(["admin.user.view", @manage])

      view = open_page(conn)

      refute has_element?(view, "#toggle-assign-roles-btn")
      assert has_element?(view, "#assign-roles-unavailable", "No roles your account can assign")

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Assigning a role needs every capability it grants"
             )

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Ask an operator to review your role."
             )
    end

    test "a user holding a grant-all role is told a role would add nothing", %{
      conn: conn,
      scope: scope
    } do
      {:ok, _} = Authz.reconcile_system_roles()

      core_admin =
        scope
        |> Authz.list_roles()
        |> Enum.find(&(&1.code == "core_admin" and &1.grant_all))

      insert_target!()
      {:ok, _} = Authz.assign_role(scope, 73, :user, 92, core_admin.id)
      grant_capabilities!(["admin.user.view", @manage])

      view = conn |> open_page() |> open_effective_permissions()

      refute has_element?(view, "#toggle-assign-roles-btn")
      assert has_element?(view, "#assign-roles-unavailable", "A role would add nothing")

      assert has_element?(
               view,
               "#assign-roles-unavailable",
               "Core Administrator already grants every capability, so this user holds everything a role could add."
             )

      # Nothing is left for the capability picker either, and it says so.
      refute has_element?(view, "#add-capabilities-section")
      assert has_element?(view, "#add-capabilities-unavailable", "No capabilities left to add")

      assert has_element?(
               view,
               "#add-capabilities-unavailable",
               "Every installed capability is already in effect or denied for this user."
             )
    end
  end

  describe "why the capability picker is absent" do
    test "when every remaining capability is one the administrator lacks, the guard is explained",
         %{conn: conn, scope: scope} do
      insert_target!()
      grant_capabilities!(["admin.user.view", @manage])

      # The user already holds the administrator's two keys directly, so what
      # remains is exactly what the administrator may not grant.
      for capability <- ["admin.user.view", @manage] do
        {:ok, :stored} = Authz.put_principal_capability(scope, 73, :user, 92, capability, true)
      end

      view = conn |> open_page() |> open_effective_permissions()

      refute has_element?(view, "#add-capabilities-section")

      assert has_element?(
               view,
               "#add-capabilities-unavailable",
               "No capabilities your account can add"
             )

      assert has_element?(
               view,
               "#add-capabilities-unavailable",
               "You can only add capabilities you hold"
             )
    end
  end
end
