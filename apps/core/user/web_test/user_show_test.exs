defmodule BilimbiWeb.UserShowTest do
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

  test "inside a workspace tile the page announces the user it shows", %{conn: conn} do
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.test"
    })

    grant_capabilities!(["admin.user.view"])
    token = Bilimbi.Base.UI.Workspace.host_token("phx-a-host")
    :ok = Bilimbi.Base.UI.Workspace.subscribe(Bilimbi.Base.UI.Workspace.topic(41, 91, token))

    {:ok, _view, _html} =
      conn
      |> log_in_as()
      |> put_req_header("sec-fetch-dest", "iframe")
      |> live(~p"/users/92?ws=#{token}")

    assert_receive {:workspace_joined}
    assert_receive {:workspace_fact, %{kind: "core/user", id: 92}}
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

    # The roles sit under the section heading, which already says Roles: the
    # count is in the heading row and the list carries no label of its own.
    assert has_element?(view, "#user-roles-heading + span", "0")
    refute has_element?(view, "#user-roles-card dt", "Roles")
    assert has_element?(view, "#user-roles-card #no-roles-msg", "No roles assigned.")

    # The section's own action sits in its heading row.
    assert has_element?(view, "#user-employees-heading + span", "0")
    assert has_element?(view, "#user-employees-card #open-add-employee-modal-btn", "Add Employee")
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
end
