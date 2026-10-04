defmodule BilimbiWeb.UserShowArchivedCompanyTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
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

    # An archived company is not in the live company list, and the page says
    # so rather than reading the account as having no company.
    assert has_element?(view, "#user-view-company", "Archived company")
    assert has_element?(view, "main header", "Archived company")
    refute has_element?(view, "#app-content", "None")
    refute has_element?(view, "#app-content", "Unaffiliated")

    # The notice stands for a viewer too: it explains the account, not the
    # reader's permission, it states archiving as final, and it says only what
    # the page blocks.
    assert has_element?(
             view,
             "#user-archived-company[role='alert']",
             "Ada Archived's company is archived, and archiving is final, so this account is read-only"
           )

    assert has_element?(view, "#user-archived-company", "nobody can sign in as or impersonate")

    assert has_element?(view, "#user-archived-company", "employee links can't be changed")
    refute has_element?(view, "#user-archived-company", "employee records")
    refute has_element?(view, "#user-archived-company", "yet")
    refute has_element?(view, "#user-archived-company", "Restore")
    refute has_element?(view, "#user-password-card")
  end

  test "an archived-company account offers an operator no editor and says why at the top",
       %{conn: conn} do
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

    grant_capabilities!([
      "admin.user.view",
      "admin.user.update",
      "admin.user.delete",
      "admin.user.impersonate"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")

    # One warning under the header, before any fact, in the shared alert.
    assert has_element?(
             view,
             "#user-archived-company[role='alert']",
             "Ada Archived's company is archived, and archiving is final, so this account is read-only"
           )

    # The facts read as text: no in-place editors, no company trigger, no
    # select, and the archived company is named as such with no link.
    assert has_element?(view, "#user-view-name", "Ada Archived")
    assert has_element?(view, "#user-view-email", "archived@example.com")
    assert has_element?(view, "#user-view-company", "Archived company")
    refute has_element?(view, "#user-name[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-email[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-company-display")
    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "#user-view-company a")

    # Nothing else that writes the account is offered: the pickers say why
    # where they would stand, and the password card, employee actions,
    # delete zone and Impersonate are absent.
    refute has_element?(view, "#toggle-assign-roles-btn")
    assert has_element?(view, "#assign-roles-unavailable", "Roles can't be changed")
    view |> element("#toggle-permissions-btn") |> render_click()
    refute has_element?(view, "#add-capabilities-section")
    assert has_element?(view, "#add-capabilities-unavailable", "Capabilities can't be changed")
    refute has_element?(view, "#user-password-card")
    refute has_element?(view, "#open-add-employee-modal-btn")
    refute has_element?(view, "#link-employee-section")
    refute has_element?(view, "#user-danger")
    refute has_element?(view, "#user-impersonate")

    # The header still offers what reading needs.
    assert has_element?(view, "#user-back[href='/users']")
    assert has_element?(view, "#user-pin")
  end

  test "an archived-company account still refuses every forged commit", %{conn: conn} do
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

    grant_capabilities!(["admin.user.view", "admin.user.update", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/95")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # A commit on a fact is refused on that fact, in the words the page used
    # before the editors were withdrawn.
    render_hook(view, "save_field", %{"id" => "95", "name" => "Ada Lovelace"})

    assert has_element?(
             view,
             "#user-name-status[role='alert']",
             "The change was not saved: this user's company is archived."
           )

    render_hook(view, "save_field", %{"id" => "95", "email" => "ada@example.com"})

    assert has_element?(
             view,
             "#user-email-status[role='alert']",
             "The change was not saved: this user's company is archived."
           )

    # The company editor does not open, and a choice that arrives anyway is
    # refused on the company fact.
    render_hook(view, "edit_field", %{"field" => "company"})
    refute has_element?(view, "#user-company-form")
    assert has_element?(view, "#user-company-status[role='alert']", "company is archived")

    render_hook(view, "save_company", %{"company_id" => "73"})
    assert has_element?(view, "#user-company-status[role='alert']", "company is archived")
    refute has_element?(view, "#user-company-status", "not in this workspace")

    # Writes that report through the flash say the same thing and open no
    # dialog or modal.
    view
    |> with_target("#user-access-panel")
    |> render_hook("assign_selected_roles", %{"role_ids" => ["1"]})

    assert has_element?(
             view,
             "#flash-error",
             "This user's company is archived, so the account can't be changed."
           )

    render_hook(view, "open_add_employee_modal", %{})
    refute has_element?(view, "#add-employee-modal")

    render_hook(view, "request_delete", %{})
    refute has_element?(view, "#delete-user-confirm")
    render_hook(view, "delete", %{})

    refute has_element?(view, "#app-content", "could not be found")

    {:ok, users} = User.list_users(scope)

    assert %{company_id: 76, name: "Ada Archived", email: "archived@example.com"} =
             Enum.find(users, &(&1.id == 95))
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
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # The zone is not offered, and a forged request is refused before any
    # dialog opens.
    refute has_element?(view, "#user-danger")

    render_hook(view, "request_delete", %{})

    refute has_element?(view, "#delete-user-confirm")

    assert has_element?(
             view,
             "#flash-error",
             "This user's company is archived, so the account can't be changed."
           )

    {:ok, users} = User.list_users(scope)
    assert Enum.any?(users, &(&1.id == 95))
  end
end
