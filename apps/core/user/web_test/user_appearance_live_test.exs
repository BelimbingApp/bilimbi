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

  test "the top bar and this form render one theme, so neither reverts the other", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, "dark"} = User.put_user_preference(scope, 73, 91, "ui.theme", "dark")

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "input[name='appearance[theme]'][value='dark'][checked]")

    render_hook(view, "shell:preference", %{kind: "theme", value: "light"})

    assert has_element?(view, "input[name='appearance[theme]'][value='light'][checked]")
    assert has_element?(view, "#app-shell[data-theme-choice='light']")

    view
    |> form("#appearance-form", %{"appearance" => %{"theme" => "light", "locale" => "de-CH"}})
    |> render_change()

    assert {:ok, "light"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert has_element?(view, "input[name='appearance[theme]'][value='light'][checked]")
    assert has_element?(view, "#app-shell[data-theme-choice='light']")
  end

  test "a time display saved from the form updates the top bar clock at once", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#app-display-company[aria-pressed='true']")
    assert has_element?(view, "#app-display-timezone", "Company")

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "system", "timezone_mode" => "utc"}
    })
    |> render_change()

    assert Bilimbi.Base.DateTime.mode(SettingsScope.user(91, 73, 41)) == :utc
    assert has_element?(view, "#appearance-timezone-mode option[value='utc'][selected]")
    assert has_element?(view, "#app-display-utc[aria-pressed='true']")
    assert has_element?(view, "#app-display-company[aria-pressed='false']")
    assert has_element?(view, "#app-display-timezone", "UTC")
  end

  test "a form save updates the top bar without a second theme copy", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#appearance-form", %{
      "appearance" => %{"theme" => "dark"}
    })
    |> render_change()

    assert render(view) =~ "Appearance settings saved."
    assert has_element?(view, "#app-shell[data-theme-choice='dark']")

    # Verify saved to User preference / settings
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "the root layout stamps data-theme only for an explicit choice", %{conn: conn} do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    # System (no stored preference): nothing stamped; prefers-color-scheme governs.
    conn = log_in_as(conn)
    refute get(conn, ~p"/settings/appearance") |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("html[data-theme]") |> Enum.any?()

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

  test "a forged unsupported locale is refused by name while the rest still save", %{conn: conn} do
    locale_scope = SettingsScope.user(91, 73, 41)
    {:ok, view, _html} = open(conn)

    view
    |> render_change("save", %{
      "appearance" => %{"theme" => "dark", "locale" => "xx-ZZ"}
    })

    refute Locale.overridden?(locale_scope)

    assert has_element?(
             view,
             "#flash-group",
             "Saved — Theme. Not saved — Language. Choose a supported value."
           )

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "the form and the top bar select from the same three time displays", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    refute has_element?(view, "#appearance-timezone-mode option[value='']")
    assert has_element?(view, "#appearance-timezone-mode option[value='company'][selected]")

    view
    |> form("#appearance-form", %{"appearance" => %{"timezone_mode" => "utc"}})
    |> render_change()

    scope = SettingsScope.user(91, 73, 41)
    assert Bilimbi.Base.DateTime.mode(scope) == :utc
    assert has_element?(view, "#appearance-timezone-mode option[value='utc'][selected]")

    view
    |> form("#appearance-form", %{"appearance" => %{"timezone_mode" => "company"}})
    |> render_change()

    assert Bilimbi.Base.DateTime.mode(scope) == :company
    assert has_element?(view, "#appearance-timezone-mode option[value='company'][selected]")
  end

  test "a top-bar time display survives the next unrelated form change", %{conn: conn} do
    {:ok, view, _html} = open(conn)
    scope = SettingsScope.user(91, 73, 41)

    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})
    assert Bilimbi.Base.DateTime.mode(scope) == :utc
    assert has_element?(view, "#appearance-timezone-mode option[value='utc'][selected]")

    view
    |> form("#appearance-form", %{"appearance" => %{"theme" => "dark"}})
    |> render_change()

    assert Bilimbi.Base.DateTime.mode(scope) == :utc
    assert has_element?(view, "#app-display-utc[aria-pressed='true']")
    assert has_element?(view, "#appearance-timezone-mode option[value='utc'][selected]")
  end

  test "an impersonated session is refused the display preferences but still saves language", %{
    conn: conn
  } do
    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> Plug.Test.init_test_session(%{
        "impersonation" => %{"original_user_id" => 92, "original_user_name" => "Grace Hopper"}
      })
      |> live(~p"/settings/appearance")

    view
    |> form("#appearance-form", %{"appearance" => %{"theme" => "dark", "locale" => "de-CH"}})
    |> render_change()

    assert has_element?(
             view,
             "#flash-group",
             "Saved — Language. Not saved — Theme. Display preferences belong to the account you are viewing."
           )

    locale_scope = SettingsScope.user(91, 73, 41)
    assert Locale.overridden?(locale_scope)
    assert Locale.locale(locale_scope) == "de-CH"
    assert has_element?(view, "#appearance-locale option[value='de-CH'][selected]")

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "rejects a forged time zone mode by name without persisting it", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # "galactic" is never a rendered option; forging the event is the point.
    view
    |> render_change("save", %{"appearance" => %{"timezone_mode" => "galactic"}})

    assert has_element?(
             view,
             "#flash-group",
             "Not saved — Time zone display. Choose a supported value."
           )

    refute Bilimbi.Base.DateTime.mode_overridden?(SettingsScope.user(91, 73, 41))
  end
end
