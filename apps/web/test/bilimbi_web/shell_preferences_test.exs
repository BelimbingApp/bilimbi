defmodule BilimbiWeb.ShellPreferencesTest do
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "shell saves theme and timezone only for the authenticated user and survives remount", %{
    conn: conn,
    scope: scope
  } do
    conn = log_in_as(conn)
    {:ok, view, _} = live(conn, ~p"/dashboard")
    render_hook(view, "shell:preference", %{kind: "theme", value: "dark", user_id: 92})
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 92, "ui.theme")
    assert has_element?(view, "#app-display-dark[aria-pressed='true']")

    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :utc
    assert DateTimePolicy.mode(SettingsScope.user(92, 73, 41)) == :company
    assert has_element?(view, "#app-shell[data-display-mode='utc']")
    {:ok, remounted, _} = live(conn, ~p"/dashboard")
    assert has_element?(remounted, "#app-display-dark[aria-pressed='true']")
    assert has_element?(remounted, "#app-display-utc[aria-pressed='true']")

    render_hook(remounted, "shell:preference", %{kind: "theme", value: "system"})
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "invalid values retain the previous preference", %{conn: conn, scope: scope} do
    {:ok, _} = User.put_user_preference(scope, 73, 91, "ui.theme", "light")
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard")
    render_hook(view, "shell:preference", %{kind: "theme", value: "sepia"})
    render_hook(view, "shell:preference", %{kind: "timezone", value: "Moon/Base"})
    render_hook(view, "shell:preference", %{value: "dark"})
    assert has_element?(view, "#app-display-light[aria-pressed='true']")
    assert {:ok, "light"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :company
  end

  test "a revoked session cannot keep changing preferences", %{conn: conn, scope: scope} do
    conn = log_in_as(conn)
    session_id = get_session(conn, "current_user")["session_id"]
    {:ok, view, _} = live(conn, ~p"/dashboard")
    :ok = Session.delete_session(session_id)
    render_hook(view, "shell:preference", %{kind: "theme", value: "dark"})
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert has_element?(view, "#app-display-system[aria-pressed='true']")
  end

  test "an impersonated session is offered no display controls and cannot write them", %{
    conn: conn,
    scope: scope
  } do
    conn =
      conn
      |> log_in_as()
      |> Plug.Test.init_test_session(%{
        "impersonation" => %{"original_user_id" => 92, "original_user_name" => "Grace Hopper"}
      })

    {:ok, view, _} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#app-scope-warning", "Viewing as Ada Lovelace")
    assert has_element?(view, "#app-display-locked", "Company time")
    refute has_element?(view, "#app-display-dark")
    refute has_element?(view, "#app-display-utc")

    render_hook(view, "shell:preference", %{kind: "theme", value: "dark"})
    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})

    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :company
  end

  test "the account menu exposes real account actions for the signed-in identity", %{conn: conn} do
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard")
    assert has_element?(view, "#app-user-toggle[aria-controls='app-user-panel']")
    assert has_element?(view, "#app-user-panel", "Ada Lovelace")
    assert has_element?(view, "#app-user-panel", "Company")
    assert has_element?(view, "#app-user-panel", "Tenant")
    assert has_element?(view, "#app-user-password[href='/settings/password']", "Change password")
    assert has_element?(view, "#app-user-logout[data-method='delete']", "Sign out")
    refute has_element?(view, "#app-tenant")
  end
end
