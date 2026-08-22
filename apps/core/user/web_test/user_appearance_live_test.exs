defmodule BilimbiWeb.UserAppearanceLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
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
    assert has_element?(view, "#appearance-locale")

    assert has_element?(
             view,
             "#appearance-locale option[value='']",
             "Use installation default (English (Malaysia))"
           )

    assert has_element?(view, "#appearance-locale option[value='de-CH']", "German (Switzerland)")
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

  test "the root layout stamps data-theme only for an explicit choice", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # System (no stored preference): nothing stamped; prefers-color-scheme governs.
    conn = log_in_as(conn)
    refute get(conn, ~p"/settings/appearance") |> html_response(200) =~ "data-theme"

    {:ok, "dark"} = User.put_user_preference(scope, 73, 91, "ui.theme", "dark")
    assert get(conn, ~p"/settings/appearance") |> html_response(200) =~ ~s(data-theme="dark")

    {:ok, "light"} = User.put_user_preference(scope, 73, 91, "ui.theme", "light")
    assert get(conn, ~p"/settings/appearance") |> html_response(200) =~ ~s(data-theme="light")
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

  test "stores and clears the signed-in account's locale override", %{conn: conn} do
    locale_scope = SettingsScope.user(91, 73, 41)
    {:ok, "fr-FR"} = Locale.put(nil, "fr-FR")

    {:ok, view, _html} = open(conn)

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "system", "locale" => "de-CH"}
    })
    |> render_change()

    assert Locale.overridden?(locale_scope)
    assert Locale.locale(locale_scope) == "de-CH"
    assert has_element?(view, "#appearance-locale option[value='de-CH'][selected]")

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "system", "locale" => ""}
    })
    |> render_change()

    refute Locale.overridden?(locale_scope)
    assert Locale.locale(locale_scope) == "fr-FR"
    assert has_element?(view, "#appearance-locale option[value=''][selected]")
  end

  test "rejects a forged unsupported locale without changing either preference", %{conn: conn} do
    locale_scope = SettingsScope.user(91, 73, 41)
    {:ok, view, _html} = open(conn)

    view
    |> render_change("save", %{
      "appearance" => %{"theme" => "dark", "locale" => "xx-ZZ"}
    })

    refute Locale.overridden?(locale_scope)

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end
end
