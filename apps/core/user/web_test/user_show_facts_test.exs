defmodule BilimbiWeb.UserShowFactsTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
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

  test "a grant on the account's current company allows a later password reset and move back",
       %{conn: conn} do
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
    grant_capabilities!(["admin.user.update"], company_id: 75)

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/users/92")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "75"})

    assert has_element?(view, "#user-company-status[role='status']", "Saved")
    assert {:ok, %{company_id: 75}} = User.get_user(scope, 75, 92)

    view |> element("#toggle-change-password-btn") |> render_click()

    view
    |> form("#user-password-form")
    |> render_submit(%{
      "password" => "newpassword123",
      "password_confirmation" => "newpassword123"
    })

    assert has_element?(view, "#flash-group", "Password updated successfully")
    refute has_element?(view, "#flash-group", "Failed to update password")

    stored_hash = UserFixtures.stored_password(92)
    assert Bilimbi.Core.User.Password.valid?("newpassword123", stored_hash)

    view |> element("#user-company-display") |> render_click()

    view
    |> form("#user-company-form")
    |> render_change(%{"company_id" => "73"})

    assert has_element?(view, "#user-company-status[role='status']", "Saved")

    refute has_element?(
             view,
             "#user-company-status",
             "you may not manage users of Beta Industries"
           )

    assert {:ok, %{company_id: 73}} = User.get_user(scope, 73, 92)
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
end
