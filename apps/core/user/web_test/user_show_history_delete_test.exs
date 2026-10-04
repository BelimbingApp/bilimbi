defmodule BilimbiWeb.UserShowHistoryDeleteTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
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

    # History is a demoted labelled disclosure, as Belimbing's admin/users/show
    # presents it: the clock beside its word, in the back link's quiet
    # treatment. It is a button because that is the disclosure contract.
    assert has_element?(
             view,
             "button#user-record-history-toggle[title='History'][aria-expanded='false'][aria-controls='user-record-history-panel']",
             "History"
           )

    assert has_element?(view, "button#user-record-history-toggle.text-link")
    assert has_element?(view, "#user-record-history-toggle .hero-clock")
    refute has_element?(view, "summary#user-record-history-toggle")

    refute has_element?(
             view,
             "main header button:not(#user-pin):not(#user-record-history-toggle)"
           )

    view |> element("#user-record-history-toggle") |> render_click()
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
    view |> element("#user-record-history-toggle") |> render_click()
    assert has_element?(view, "#user-record-history-empty")

    # The page's own Updated fact follows the write; the open trail must too.
    # A trail that stood still here was the loophole: the row was captured,
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
    assert has_element?(view, "#user-record-history-toggle[aria-expanded='false']")
    refute has_element?(view, "#user-record-history-panel")
    refute has_element?(view, "#user-record-history[phx-click-away]")
    refute has_element?(view, "#user-record-history details")

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
    # across the patch that carries it. Focus moves into the panel; Escape
    # from inside closes it and returns focus to the trigger, and focus
    # leaving it closes it where the user is.
    view |> element("#user-record-history-toggle") |> render_click()
    assert has_element?(view, "#user-record-history-toggle[aria-expanded='true']")

    assert has_element?(
             view,
             "#user-record-history-panel[tabindex='-1'][phx-mounted]"
           )

    assert has_element?(view, "#user-record-history-entry-#{mutation.id}", "old@example.com")

    panel =
      view
      |> element("#user-record-history-panel")
      |> render()
      |> LazyHTML.from_fragment()

    assert [mounted] = LazyHTML.attribute(panel, "phx-mounted")
    assert [["focus", focus]] = JSON.decode!(mounted)
    refute Map.has_key?(focus, "to")

    disclosure =
      view
      |> element("#user-record-history[phx-hook='DisclosureDismiss']")
      |> render()
      |> LazyHTML.from_fragment()

    assert [escape] = LazyHTML.attribute(disclosure, "data-escape")

    assert [["push", %{"event" => "close"}], ["focus", %{"to" => "#user-record-history-toggle"}]] =
             JSON.decode!(escape)

    assert [dismiss] = LazyHTML.attribute(disclosure, "data-dismiss")
    assert [["push", %{"event" => "close"}]] = JSON.decode!(dismiss)

    view |> with_target("#user-record-history") |> render_hook("close", %{})
    assert has_element?(view, "#user-record-history-toggle[aria-expanded='false']")
    refute has_element?(view, "#user-record-history-panel")
    refute has_element?(view, "#user-record-history[phx-click-away]")

    view |> element("#user-record-history-toggle") |> render_click()
    assert has_element?(view, "#user-record-history-toggle[aria-expanded='true']")

    view |> element("#user-record-history-toggle") |> render_click()
    assert has_element?(view, "#user-record-history-toggle[aria-expanded='false']")
    refute has_element?(view, "#user-record-history-panel")
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

  test "refuses deletion when admin.user.delete is revoked after the dialog opens", %{conn: conn} do
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
    assert has_element?(view, "#delete-user-confirm-confirm")

    {:ok, scope} = Tenancy.scope(41)
    revoke_user_delete!(scope)

    view |> element("#delete-user-confirm-confirm") |> render_click()

    assert has_element?(view, "#flash-error", "You do not have permission to delete users.")
    assert {:ok, %{name: "Grace Hopper"}} = User.get_user(scope, 73, 92)
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

  defp revoke_user_delete!(scope) do
    grant =
      scope
      |> Authz.list_principal_capabilities(page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.user.delete"))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)
  end

  defp assert_redirected_with_flash(view, to) do
    assert {path, _flash} = assert_redirect(view)
    assert path == to
  end
end
