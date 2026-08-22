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

  test "renders the honest light-only theme state and the locale select", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#appearance-form")
    # No radio saves a dead choice while rendering is light-only (#657);
    # the ui.theme storage contract stays intact underneath.
    refute has_element?(view, "input[name='appearance[theme]']")
    assert has_element?(view, "#theme-current", "Light")
    assert has_element?(view, "#theme-current", "currently renders the light theme")
    assert has_element?(view, "#appearance-locale")

    assert has_element?(
             view,
             "#appearance-locale option[value='']",
             "Use installation default (English (Malaysia))"
           )

    assert has_element?(view, "#appearance-locale option[value='de-CH']", "German (Switzerland)")
  end

  test "ui.theme storage stays intact as the future foundation's contract", %{conn: conn} do
    # The control is gone from the screen (#657), but the preference API —
    # the consumer contract the dark-theme foundation will read — still
    # stores and validates the value, and a stored non-light choice renders
    # the page without resurrecting dead controls.
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "dark"} = User.put_user_preference(scope, 73, 91, "ui.theme", "dark")

    {:ok, view, _html} = open(conn)
    refute has_element?(view, "input[name='appearance[theme]']")
    assert has_element?(view, "#theme-current", "Light")
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "stores and clears the signed-in account's locale override", %{conn: conn} do
    locale_scope = SettingsScope.user(91, 73, 41)
    {:ok, "fr-FR"} = Locale.put(nil, "fr-FR")

    {:ok, view, _html} = open(conn)

    view
    |> form("#appearance-form", %{
      "appearance" => %{"locale" => "de-CH"}
    })
    |> render_change()

    assert Locale.overridden?(locale_scope)
    assert Locale.locale(locale_scope) == "de-CH"
    assert has_element?(view, "#appearance-locale option[value='de-CH'][selected]")

    view
    |> form("#appearance-form", %{
      "appearance" => %{"locale" => ""}
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

  test "stores and clears the signed-in account's time zone display mode", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#appearance-timezone-mode option[value='']")
    assert has_element?(view, "#appearance-timezone-mode option[value='utc']")

    view
    |> form("#appearance-form", %{"appearance" => %{"timezone_mode" => "utc"}})
    |> render_change()

    scope = SettingsScope.user(91, 73, 41)
    assert Bilimbi.Base.DateTime.mode(scope) == :utc
    assert Bilimbi.Base.DateTime.mode_overridden?(scope)

    view
    |> form("#appearance-form", %{"appearance" => %{"timezone_mode" => ""}})
    |> render_change()

    refute Bilimbi.Base.DateTime.mode_overridden?(scope)
    assert Bilimbi.Base.DateTime.mode(scope) == :company
  end

  test "rejects a forged time zone mode without persisting it", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # "galactic" is never a rendered option; forging the event is the point.
    view
    |> render_change("save", %{"appearance" => %{"timezone_mode" => "galactic"}})

    assert has_element?(view, "#flash-group", "Choose a supported theme, locale, and time zone display.")
    refute Bilimbi.Base.DateTime.mode_overridden?(SettingsScope.user(91, 73, 41))
  end
end
