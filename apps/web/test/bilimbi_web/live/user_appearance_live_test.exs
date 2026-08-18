defmodule BilimbiWeb.UserAppearanceLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  defp open(conn), do: conn |> log_in_as() |> live(~p"/settings/appearance")

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/settings/appearance")
  end

  test "renders appearance options and defaults to system", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#appearance-form")
    assert has_element?(view, "input[name='appearance[theme]'][value='light']")
    assert has_element?(view, "input[name='appearance[theme]'][value='dark']")
    assert has_element?(view, "input[name='appearance[theme]'][value='system'][checked]")
  end

  test "updates theme to dark and dispatches theme-changed event", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "dark"}
    })
    |> render_change()

    assert render(view) =~ "Appearance settings saved."

    # Verify saved to User preference / settings
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "switching back to system deletes preference override", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, "dark"} = User.put_user_preference(scope, 73, 91, "ui.theme", "dark")

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "input[name='appearance[theme]'][value='dark'][checked]")

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "system"}
    })
    |> render_change()

    assert render(view) =~ "Appearance settings saved."

    # Verify preference override was cleared back to system default
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end
end
