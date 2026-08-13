defmodule BilimbiWeb.LoginLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company

  setup do
    Bilimbi.Core.User.TestFixtures.create_user_tables!()
    :ok
  end

  test "sends a restrictive content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "script-src 'self'"
  end

  test "the homepage is the sign-in screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#auth-card")
    assert has_element?(view, "#login-form[action='/session'][method='post']")
    assert has_element?(view, "#login-email[autocomplete='email']")
    assert has_element?(view, "#login-password[autocomplete='current-password']")
    assert has_element?(view, "#login-submit", "Log in")
  end

  test "validates required fields without leaving the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#login-form", login: %{email: "", password: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "rejects wrong credentials with Belimbing's neutral error", %{conn: conn} do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#login-form", login: %{email: "ada@example.com", password: "wr0ng-wr0ng-wr0ng"})
      |> render_submit()

    assert html =~ "These credentials do not match our records."
  end

  test "signs in with valid credentials and opens the workspace", %{conn: conn} do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})
    Company.TestFixtures.assign_primary_company!(41, 73)

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    assert {:ok, _user} =
             Bilimbi.Core.User.register_user(scope, 73, %{
               name: "Ada Lovelace",
               email: "ada@example.com",
               password: "c0rrect-horse-battery"
             })

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#login-form",
      login: %{email: "ada@example.com", password: "c0rrect-horse-battery"}
    )
    |> render_submit()

    # The two-phase Belimbing handoff: the LiveView paints the confirmed
    # state and arms the session form for full navigation.
    assert has_element?(view, "#login-opening", "Signed in. Opening your workspace…")
    assert has_element?(view, "#login-submit[disabled]")
    assert has_element?(view, "#login-form[phx-trigger-action]")

    # The armed form carries a token the session controller accepts.
    assert render(view) =~ "login[_token]"
  end

  test "locks out after five failed attempts", %{conn: conn} do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})

    {:ok, view, _html} = live(conn, ~p"/")

    for _ <- 1..5 do
      view
      |> form("#login-form", login: %{email: "ada@example.com", password: "wr0ng-wr0ng"})
      |> render_submit()
    end

    html =
      view
      |> form("#login-form", login: %{email: "ada@example.com", password: "wr0ng-wr0ng"})
      |> render_submit()

    assert html =~ "Too many sign-in attempts"

    BilimbiWeb.RateLimit.reset({:login, "ada@example.com", "127.0.0.1"})
  end

  test "the throttle keys on email+IP, so one email's failures do not lock out another",
       %{conn: conn} do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})

    {:ok, view, _html} = live(conn, ~p"/")

    for _ <- 1..5 do
      view
      |> form("#login-form", login: %{email: "ada@example.com", password: "not-the-password"})
      |> render_submit()
    end

    # A different email from the same IP is still allowed -- Belimbing keys
    # the throttle on email|ip, so one loud neighbor cannot lock out a NAT.
    html =
      view
      |> form("#login-form", login: %{email: "grace@example.com", password: "not-the-password"})
      |> render_submit()

    refute html =~ "Too many sign-in attempts"
    assert html =~ "These credentials do not match our records."

    BilimbiWeb.RateLimit.reset({:login, "ada@example.com", "127.0.0.1"})
    BilimbiWeb.RateLimit.reset({:login, "grace@example.com", "127.0.0.1"})
  end

  test "shows the live platform workspace identity below the card", %{conn: conn} do
    assert {:ok, identity} =
             Company.provision_platform_operator("Platform operator", %{
               name: "Bilimbi Operations",
               legal_name: "Bilimbi Operations Sdn. Bhd.",
               code: "bilimbi_operations"
             })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#login-workspace[data-state='ready']")
    assert has_element?(view, "#login-workspace", "Bilimbi Operations Sdn. Bhd.")

    assert has_element?(
             view,
             "#login-workspace",
             "tenant #{identity.tenant.id}"
           )
  end

  test "shows an honest workspace state when identity is absent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#login-workspace[data-state='not_provisioned']")
  end

  test "redirects a signed-in visitor to the dashboard", %{conn: conn} do
    Company.TestFixtures.insert_tenant!(%{id: 41})
    Company.TestFixtures.insert_company!(%{id: 73, tenant_id: 41})
    Bilimbi.Core.User.TestFixtures.insert_user!(%{id: 91, company_id: 73})

    conn = log_in_as(conn)

    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/")
  end
end
