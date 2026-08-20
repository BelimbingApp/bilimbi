defmodule BilimbiWeb.SystemLocalizationLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Locale.Bootstrap
  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn) do
    grant_capabilities!("admin.system.localization.manage")
    conn |> log_in_as() |> live(~p"/system/localization")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/localization")
  end

  test "redirects away without the localization capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/localization")
  end

  test "shows the supported catalogue and inferred provenance honestly", %{conn: conn} do
    assert %{locale: "de-DE"} = Locale.resolve(nil, %Bootstrap{country_iso: "DE"})

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "h1", "Language & Region")
    assert has_element?(view, "#localization-locale-select option[value='de-DE'][selected]")

    assert has_element?(
             view,
             "#localization-locale-select option[value='fr-FR']",
             "French (France)"
           )

    assert has_element?(view, "#localization-language", "de")

    assert has_element?(
             view,
             "#localization-source",
             "Inferred from platform-operator company address"
           )

    assert has_element?(view, "#localization-inferred-country", "DE")
    assert has_element?(view, "#localization-message-catalogues", "en")
    assert render(view) =~ "Regional support does not imply"
    assert has_element?(view, "#nav-admin-system-localization[aria-current='page']")
  end

  test "stores a supported manual locale and clears stale inferred country", %{conn: conn} do
    assert %{source: "platform_operator_address"} =
             Locale.resolve(nil, %Bootstrap{country_iso: "DE"})

    {:ok, view, _html} = open(conn)

    view
    |> form("#localization-form", localization: %{locale: "fr-FR"})
    |> render_submit()

    assert %{locale: "fr-FR", language: "fr", source: "manual", inferred_country: nil} =
             Locale.resolve(nil)

    assert Settings.get("ui.locale_source", nil) == "manual"
    assert Settings.get("ui.locale_inferred_country", nil) == nil
    assert has_element?(view, "#localization-source", "Selected manually")
    assert has_element?(view, "#localization-inferred-country", "Not recorded")
    assert render(view) =~ "Installation locale saved."
  end

  test "rejects forged unsupported input without changing locale or provenance", %{conn: conn} do
    assert %{locale: "en-US", source: "platform_operator_address"} =
             Locale.resolve(nil, %Bootstrap{country_iso: "US"})

    {:ok, view, _html} = open(conn)

    render_submit(view, "save", %{"localization" => %{"locale" => "en_us"}})

    assert %{
             locale: "en-US",
             source: "platform_operator_address",
             inferred_country: "US"
           } = Locale.resolve(nil)

    assert render(view) =~ "Choose a supported locale."
  end
end
