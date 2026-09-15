defmodule BilimbiWeb.ThemeControllerTest do
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    SettingsFixtures.create_settings_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    :ok
  end

  test "POST /api/theme requires authentication", %{conn: conn} do
    conn = post(conn, ~p"/api/theme", %{"theme" => "dark"})
    assert redirected_to(conn) == ~p"/"
  end

  test "POST /api/theme updates user theme preference", %{conn: conn} do
    conn =
      conn
      |> log_in_as()
      |> post(~p"/api/theme", %{"theme" => "dark"})

    assert json_response(conn, 200) == %{"theme" => "dark"}

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "POST /api/theme with system clears override", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, "dark"} = User.put_user_preference(scope, 73, 91, "ui.theme", "dark")

    conn =
      conn
      |> log_in_as()
      |> post(~p"/api/theme", %{"theme" => "system"})

    assert json_response(conn, 200) == %{"theme" => "system"}
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "POST /api/theme rejects invalid theme values", %{conn: conn} do
    conn =
      conn
      |> log_in_as()
      |> post(~p"/api/theme", %{"theme" => "sepia"})

    assert json_response(conn, 422) == %{"error" => "invalid_theme"}
  end

  test "an impersonated session cannot write the viewed account's theme", %{conn: conn} do
    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    conn =
      conn
      |> log_in_as()
      |> Plug.Test.init_test_session(%{
        "impersonation" => %{"original_user_id" => 92, "original_user_name" => "Grace Hopper"}
      })
      |> post(~p"/api/theme", %{"theme" => "dark"})

    assert json_response(conn, 403) == %{"error" => "impersonating"}

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "a failed user preference write does not report success", %{conn: conn} do
    authenticated = conn |> log_in_as() |> get(~p"/settings/appearance")
    current_scope = authenticated.assigns.current_scope
    :ok = User.delete_user(current_scope.scope, 73, 91)

    response =
      build_conn()
      |> assign(:current_scope, current_scope)
      |> BilimbiWeb.ThemeController.update(%{"theme" => "dark"})

    assert json_response(response, 503) == %{"error" => "save_failed"}
  end
end
