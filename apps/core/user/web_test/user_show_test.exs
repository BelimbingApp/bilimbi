defmodule BilimbiWeb.UserShowTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
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

    assert has_element?(
             view,
             "#user-pin[data-nav-pin-record='true'][data-nav-pin-label='Administration / Users / Grace Hopper'][data-nav-pin-url='/users/92']"
           )

    assert has_element?(view, "#user-back[href='/users']", "Back")
    assert has_element?(view, "a[href='/companies/73']", "Bilimbi Industries")
    assert has_element?(view, "#app-content", "unverified")
    refute has_element?(view, "#user-edit")
    refute has_element?(view, "#user-danger")
    refute has_element?(view, "#user-archived-company")

    # A viewer sees the facts with no affordance: no in-place editors and no
    # company trigger, and the header holds no button beyond the pin.
    assert has_element?(view, "#user-view-name", "Grace Hopper")
    assert has_element?(view, "#user-view-email", "grace@example.com")
    refute has_element?(view, "#user-name[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-email[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-company-display")
    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "main header button:not(#user-pin)")
  end

  test "an actor without admin.user.update sees no company select, no warning and no editors",
       %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # The company is a link to the company, not a trigger; the select and its
    # warning never render, and no text fact carries an editor.
    assert has_element?(view, "#user-view-company a[href='/companies/73']", "Bilimbi Industries")
    refute has_element?(view, "#user-company-display")
    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "#user-company-select")
    refute has_element?(view, "#user-company-warning")
    refute has_element?(view, "#user-name[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-email[phx-hook='InlineEdit']")

    # A forged change from that actor is refused and writes nothing.
    render_hook(view, "edit_field", %{"field" => "company"})
    refute has_element?(view, "#user-company-form")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, %{company_id: 73}} = User.get_user(scope, 73, 92)
  end

  test "presents the user facts as the shared list under one section heading", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # One heading treatment: every section is a named region whose title is
    # the shared level-two heading, and the fact sections write no h3.
    for id <- ~w(user-details user-roles user-employees user-external-accesses) do
      assert has_element?(
               view,
               "##{id}-card[role='region'][aria-labelledby='#{id}-heading'] h2##{id}-heading"
             )
    end

    refute has_element?(view, "#user-details-card h3")
    refute has_element?(view, "#user-employees-card h3")
    refute has_element?(view, "#user-external-accesses-card h3")
    refute has_element?(view, "#user-details-card dl.grid")

    # The facts are rows of one definition list; every value cell keeps its
    # id and the in-place editor opens inside it.
    assert has_element?(view, "#user-details-card dl dd#user-view-name", "Grace Hopper")
    assert has_element?(view, "dd#user-view-name #user-name[phx-hook='InlineEdit']")
    assert has_element?(view, "#user-details-card dl dd#user-view-email", "grace@example.com")
    assert has_element?(view, "#user-details-card dl dt", "Company")
    assert has_element?(view, "dd#user-view-company #user-company-display", "Bilimbi Industries")
    assert has_element?(view, "dd#user-view-email-verified", "unverified")
    assert has_element?(view, "#user-details-card dl dt", "Created")
    assert has_element?(view, "dd#user-view-created")
    assert has_element?(view, "dd#user-view-updated")

    # Roles are a fact of the same shape, with the count in the heading row.
    assert has_element?(view, "#user-roles-heading + span", "0")
    assert has_element?(view, "#assigned-roles-container dt", "Roles")
    assert has_element?(view, "dd#assigned-roles #no-roles-msg", "No roles assigned.")

    # The section's own action sits in its heading row.
    assert has_element?(view, "#user-employees-heading + span", "0")
    assert has_element?(view, "#user-employees-card #open-add-employee-modal-btn", "Add Employee")
  end

  test "hides History and Impersonate from an actor without their capabilities", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    # Holding the update capability changes the facts, not the header:
    # History needs admin.audit.log.list and Impersonate needs
    # admin.user.impersonate, and neither is granted here.
    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    assert has_element?(view, "#user-name[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-record-history-toggle")
    refute has_element?(view, "#user-record-history")
    refute has_element?(view, "#user-impersonate")
    assert has_element?(view, "main header #user-back", "Back")
    refute has_element?(view, "main header button:not(#user-pin)")
    refute has_element?(view, "#user-edit")
  end

  test "shows record history for the user's compatible auditable identity", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, _mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: User.notifiable_identity(),
        auditable_id: "92",
        subject_name: "Grace Hopper",
        event: "updated",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{"email" => "old@example.com"},
        new_values: %{"email" => "grace@example.com"}
      })

    grant_capabilities!(["admin.user.view", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")

    # History is a demoted labelled action, as Belimbing's admin/users/show
    # presents it: the clock beside its word, in the back link's quiet
    # treatment, never a button.
    assert has_element?(view, "summary#user-record-history-toggle[title='History']", "History")
    assert has_element?(view, "summary#user-record-history-toggle.text-link")
    assert has_element?(view, "#user-record-history-toggle .hero-clock")
    refute has_element?(view, "button#user-record-history-toggle")
    refute has_element?(view, "main header button:not(#user-pin)")
    assert has_element?(view, "#user-record-history-panel", "old@example.com")
    assert has_element?(view, "#user-record-history-panel", "grace@example.com")
  end

  test "an in-place name edit appears in the record history without a remount", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    assert has_element?(view, "#user-record-history-empty")

    # The page's own Updated fact follows the write; the trail must too. A
    # trail that stood still here was the loophole: the row was captured,
    # and the panel never re-read it because the record's id had not changed.
    render_hook(view, "save_field", %{"id" => "92", "name" => "Grace Brewster Hopper"})
    assert has_element?(view, "h1", "Grace Brewster Hopper")

    refute has_element?(view, "#user-record-history-empty")
    assert has_element?(view, "#user-record-history-panel", "1 recent mutation")
    assert has_element?(view, "#user-record-history-panel", "Updated")
    assert has_element?(view, "#user-record-history-panel", "Grace Hopper")
    assert has_element?(view, "#user-record-history-panel", "Grace Brewster Hopper")
    assert has_element?(view, "#user-record-history-panel", "User #91")
  end

  test "opening the record history re-reads it and the open state is the server's", %{
    conn: conn
  } do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.audit.log.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    assert has_element?(view, "#user-record-history-empty")
    refute has_element?(view, "#user-record-history details[open]")

    # A write from elsewhere — another session, a job — lands after mount.
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: User.notifiable_identity(),
        auditable_id: "92",
        subject_name: "Grace Hopper",
        event: "updated",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{"email" => "old@example.com"},
        new_values: %{"email" => "grace@example.com"}
      })

    # Opening the panel shows the trail as of now, and the panel stays open
    # across the patch that carries it.
    view |> element("#user-record-history-toggle") |> render_click()
    assert has_element?(view, "#user-record-history details[open]")
    assert has_element?(view, "#user-record-history-entry-#{mutation.id}", "old@example.com")

    view |> element("#user-record-history-toggle") |> render_click()
    refute has_element?(view, "#user-record-history details[open]")
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
    # There is no edit mode to reach: the facts edit in place.
    refute has_element?(view, "#user-edit")
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

    # Deleting confirms through the shared dialog, which names the account and
    # says what cannot be undone; no native confirm remains.
    refute has_element?(view, "#user-delete[data-confirm]")
    view |> element("#user-delete") |> render_click()

    assert_modal_dialog(view, "delete-user-confirm", "Grace Hopper's account will be deleted.")
    assert has_element?(view, "dialog#delete-user-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#delete-user-confirm-description",
             "They can no longer sign in. This cannot be undone."
           )

    # Cancelling keeps the account on its page.
    view |> element("#delete-user-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#delete-user-confirm")
    assert has_element?(view, "#user-delete")

    # Confirming deletes and leaves for the list.
    view |> element("#user-delete") |> render_click()

    assert has_element?(
             view,
             "#delete-user-confirm-confirm[phx-disable-with='Deleting…']",
             "Delete"
           )

    view |> element("#delete-user-confirm-confirm") |> render_click()

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

    # An archived company is not in the live company list, and the page says
    # so rather than reading the account as having no company.
    assert has_element?(view, "#user-view-company", "Archived company")
    assert has_element?(view, "main header", "Archived company")
    refute has_element?(view, "#app-content", "None")
    refute has_element?(view, "#app-content", "Unaffiliated")

    # The notice stands for a viewer too: it explains the account, not the
    # reader's permission, and it promises no restore the product lacks.
    assert has_element?(
             view,
             "#user-archived-company[role='alert']",
             "Ada Archived's company is archived, so this account is read-only"
           )

    assert has_element?(view, "#user-archived-company", "nobody can sign in as or impersonate")

    assert has_element?(
             view,
             "#user-archived-company",
             "has no way to restore an archived company"
           )

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
             "Ada Archived's company is archived, so this account is read-only"
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
    render_hook(view, "assign_selected_roles", %{"role_ids" => ["1"]})

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

  test "refuses to delete the signed-in account", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    grant_capabilities!(["admin.user.view", "admin.user.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/91")

    # The signed-in account is refused before any dialog opens.
    view |> element("#user-delete") |> render_click()

    refute has_element?(view, "#delete-user-confirm")
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

    # Impersonate is the quiet labelled action Belimbing presents beside
    # History and Back: its glyph and its word as a POST link in the demoted
    # treatment, not a bordered or primary button.
    assert has_element?(
             view,
             "a#user-impersonate[href='/admin/impersonate/92'][data-method='post'][title='Impersonate this user']",
             "Impersonate"
           )

    assert has_element?(view, "a#user-impersonate.text-link svg")
    refute has_element?(view, "a#user-impersonate.border")
    refute has_element?(view, "a#user-impersonate.bg-action")
    refute has_element?(view, "button#user-impersonate")
    refute has_element?(view, "main header button:not(#user-pin)")

    # When viewing own profile, impersonate action is hidden
    {:ok, own_view, _html} = conn |> log_in_as() |> live(~p"/users/91")
    refute has_element?(own_view, "#user-impersonate")
  end

  test "saves each committed text fact in place and reports the outcome on that fact", %{
    conn: conn
  } do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    assert has_element?(view, "#user-name[phx-hook='InlineEdit']")
    refute has_element?(view, "#user-name[data-allow-empty]")
    refute has_element?(view, "#user-name-status")

    render_hook(view, "save_field", %{"id" => "92", "name" => "Grace Brewster Hopper"})
    assert has_element?(view, "h1", "Grace Brewster Hopper")
    assert has_element?(view, "#user-view-name", "Grace Brewster Hopper")
    assert has_element?(view, "#user-name-status[role='status']", "Saved")
    refute has_element?(view, "#flash-group", "updated")
    assert {:ok, %{name: "Grace Brewster Hopper"}} = User.get_user(scope, 73, 92)

    # "Saved" belongs to the most recent commit only.
    render_hook(view, "save_field", %{"id" => "92", "email" => "grace.hopper@example.com"})
    assert has_element?(view, "#user-view-email", "grace.hopper@example.com")
    assert has_element?(view, "#user-email-status[role='status']", "Saved")
    refute has_element?(view, "#user-name-status")
    assert {:ok, %{email: "grace.hopper@example.com"}} = User.get_user(scope, 73, 92)
  end

  test "a refused commit keeps the stored value on screen and reports the reason on the fact", %{
    conn: conn
  } do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    render_hook(view, "save_field", %{"id" => "92", "email" => "invalid-email"})

    assert has_element?(view, "#user-email-status[role='alert']", "was not saved")
    assert has_element?(view, "#user-email-status", "\"invalid-email\"")
    assert has_element?(view, "#user-email-status", "Email must be an email address")
    assert has_element?(view, "#user-view-email", "grace@example.com")
    assert has_element?(view, "#user-email input[aria-invalid='true']")
    refute has_element?(view, "#user-email-status", "Saved")
    refute has_element?(view, "#flash-group", "was not saved")
    refute has_element?(view, "#flash-group", "Failed")
    assert {:ok, %{email: "grace@example.com"}} = User.get_user(scope, 73, 92)

    # The alert stays until that fact is committed again, and then gives way
    # to the new outcome; a success elsewhere does not clear it.
    render_hook(view, "save_field", %{"id" => "92", "name" => "Grace B. Hopper"})
    assert has_element?(view, "#user-email-status[role='alert']")
    assert has_element?(view, "#user-name-status", "Saved")

    # A taken address is refused by the unique constraint, with its own reason.
    render_hook(view, "save_field", %{"id" => "92", "email" => "ada@example.com"})
    assert has_element?(view, "#user-email-status[role='alert']", "Email has already been taken")
    refute has_element?(view, "#user-name-status")

    render_hook(view, "save_field", %{"id" => "92", "email" => "grace.hopper@example.com"})
    refute has_element?(view, "#user-email-status[role='alert']")
    assert has_element?(view, "#user-email-status", "Saved")
    assert has_element?(view, "#user-view-email", "grace.hopper@example.com")
  end

  test "the company select offers companies only and warns before the change commits", %{
    conn: conn
  } do
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
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # The company reads as its name and becomes a select on click, like
    # Belimbing's edit-in-place select; nothing is a permanent control, and
    # the warning belongs to the open editor, not to the read state.
    assert has_element?(view, "#user-company-display", "Bilimbi Industries")
    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "select#user-company-select")
    refute has_element?(view, "#user-company-warning")

    view |> element("#user-company-display") |> render_click()
    assert has_element?(view, "#user-company-form select#user-company-select")
    assert has_element?(view, "#user-company-select option[value='73']", "Bilimbi Industries")
    assert has_element?(view, "#user-company-select option[value='75']", "Beta Industries")

    # A user always belongs to a company: the select offers companies only,
    # with no blank option to detach the account. Belimbing offers "None"
    # here; Bilimbi has no screen that could reopen a detached account.
    refute has_element?(view, "#user-company-select option[value='']")
    refute has_element?(view, "#user-company-select option", "None")

    # The reassignment ends every session the account holds, so the open
    # editor says so before the operator chooses, and the select is
    # described by that warning for assistive technology.
    assert has_element?(
             view,
             "#user-company-warning",
             "Changing the company signs Grace Hopper out of every session."
           )

    assert has_element?(view, "#user-company-select[aria-describedby='user-company-warning']")

    # Escape or leaving the select cancels without writing.
    render_hook(view, "cancel_edit_field", %{})
    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "#user-company-warning")
    assert {:ok, %{company_id: 73}} = User.get_user(scope, 73, 92)

    # Reassign company to 75: commits on change, with no second click, and
    # reports on the fact.
    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "75"})

    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "#user-company-clear-confirm")
    assert has_element?(view, "#user-company-display", "Beta Industries")
    assert has_element?(view, "#user-company-status[role='status']", "Saved")
    refute has_element?(view, "#flash-group", "reassigned")
    assert has_element?(view, "main header", "Beta Industries")
    assert {:ok, %{company_id: 75}} = User.get_user(scope, 75, 92)

    {:ok, mutations} = Audit.list_mutations(scope)
    assert Enum.count(mutations, &(&1.event == "reassigned_company")) == 1

    # The account keeps a company, so its text facts keep their editors.
    assert has_element?(view, "#user-name[phx-hook='InlineEdit']")
    assert has_element?(view, "#user-email[phx-hook='InlineEdit']")

    # A blank value the select never offered is a forged or stale
    # submission: it writes nothing, detaches nothing, and the fact says
    # why in the product's own words.
    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => ""})

    refute has_element?(view, "#user-company-form")
    refute has_element?(view, "#user-company-clear-confirm")
    assert has_element?(view, "#user-company-status[role='alert']", "was not saved")
    assert has_element?(view, "#user-company-status", "a user always belongs to a company")
    refute has_element?(view, "#user-company-status", "Saved")
    assert has_element?(view, "#user-company-display", "Beta Industries")
    assert {:ok, %{company_id: 75}} = User.get_user(scope, 75, 92)

    {:ok, mutations} = Audit.list_mutations(scope)
    refute Enum.any?(mutations, &(&1.event == "cleared_company"))
    refute has_element?(view, "#user-unaffiliated-notice")
  end

  test "a refused reassignment names the company the rule was evaluated against", %{
    conn: conn
  } do
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

    # admin.user.update on company 73 only. The reassign authorizes against
    # 73 and lands; every later write on this account authorizes against 75.
    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "75"})

    assert has_element?(view, "#user-company-status[role='status']", "Saved")
    assert {:ok, %{company_id: 75}} = User.get_user(scope, 75, 92)

    # Moving the account back authorizes against Beta Industries, the
    # account's CURRENT company, so the refusal names that company and the
    # choice that was refused, not the company that was chosen.
    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "73"})

    assert has_element?(view, "#user-company-status[role='alert']", "was not saved")
    assert has_element?(view, "#user-company-status", "\"Bilimbi Industries\"")

    assert has_element?(
             view,
             "#user-company-status",
             "you may not manage users of Beta Industries"
           )

    refute has_element?(view, "#user-company-status", "that company")
    assert has_element?(view, "#user-company-display", "Beta Industries")
    assert {:ok, %{company_id: 75}} = User.get_user(scope, 75, 92)
  end

  test "a refused company choice keeps the stored company and reports the reason on the fact",
       %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!(["admin.user.view", "admin.user.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # Company 74 belongs to another tenant and is not an option; a forged
    # change is refused by Core User and the refusal lands on the fact.
    view |> element("#user-company-display") |> render_click()
    refute has_element?(view, "#user-company-select option[value='74']")

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "74"})

    refute has_element?(view, "#user-company-form")
    assert has_element?(view, "#user-company-status[role='alert']", "was not saved")
    assert has_element?(view, "#user-company-status", "\"74\"")
    assert has_element?(view, "#user-company-display", "Bilimbi Industries")
    refute has_element?(view, "#user-company-status", "Saved")
    refute has_element?(view, "#flash-group", "Failed")
    assert {:ok, %{company_id: 73}} = User.get_user(scope, 73, 92)

    # A later success elsewhere leaves the refusal standing on its fact.
    render_hook(view, "save_field", %{"id" => "92", "name" => "Grace B. Hopper"})
    assert has_element?(view, "#user-company-status[role='alert']")
    assert has_element?(view, "#user-name-status", "Saved")
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
    render_click(view, "remove_role", %{})
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

  defp assert_redirected_with_flash(view, to) do
    assert {path, _flash} = assert_redirect(view)
    assert path == to
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
