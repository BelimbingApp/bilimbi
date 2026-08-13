defmodule BilimbiWeb.GeonamesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    :ok
  end

  describe "countries" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/geonames/countries")
    end

    test "redirects away when the actor lacks admin.geonames.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/geonames/countries")
    end

    test "explains that empty reference data is normal", %{conn: conn} do
      grant_capabilities!(["admin.geonames.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/geonames/countries")

      assert has_element?(view, "#countries-empty", "No country reference data has been imported")
    end

    test "lists imported countries", %{conn: conn} do
      GeonamesFixtures.insert_country!()
      grant_capabilities!(["admin.geonames.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/geonames/countries")

      assert has_element?(view, "#geonames-countries td", "Malaysia")
      assert has_element?(view, "#geonames-countries code", "MY")
    end
  end

  describe "administrative divisions" do
    test "lists the divisions for the selected country", %{conn: conn} do
      GeonamesFixtures.insert_country!()
      GeonamesFixtures.insert_admin1!()
      grant_capabilities!(["admin.geonames.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/geonames/admin1")

      view
      |> form("#admin1-country-form", admin1: %{country_iso: "MY"})
      |> render_change()

      assert has_element?(view, "#geonames-admin1 td", "Kuala Lumpur")
      assert has_element?(view, "#geonames-admin1 code", "MY.14")
    end
  end

  describe "postcode lookup" do
    test "searches by country and exact postcode without listing the whole dataset", %{conn: conn} do
      GeonamesFixtures.insert_country!()
      GeonamesFixtures.insert_postcode!()
      grant_capabilities!(["admin.geonames.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

      view
      |> form("#postcode-lookup-form", postcode_lookup: %{country_iso: "MY", postcode: "50000"})
      |> render_submit()

      assert has_element?(view, "#geonames-postcodes code", "50000")
      assert has_element?(view, "#geonames-postcodes td", "Kuala Lumpur")
    end

    test "reports an empty exact lookup honestly", %{conn: conn} do
      GeonamesFixtures.insert_country!()
      grant_capabilities!(["admin.geonames.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

      view
      |> form("#postcode-lookup-form", postcode_lookup: %{country_iso: "MY", postcode: "99999"})
      |> render_submit()

      assert has_element?(view, "#postcode-empty", "No postcode matches")
    end
  end
end
