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
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    GeonamesFixtures.insert_country!()

    GeonamesFixtures.insert_country!(%{
      iso: "US",
      iso3: "USA",
      iso_numeric: "840",
      country: "United States",
      capital: "Washington",
      continent: "NA",
      currency_code: "USD",
      currency_name: "Dollar",
      geoname_id: 6_252_001
    })

    GeonamesFixtures.insert_admin1!()
    GeonamesFixtures.insert_admin1!(%{code: "US.CA", name: "California", geoname_id: 5_332_921})
    GeonamesFixtures.insert_postcode!()

    GeonamesFixtures.insert_postcode!(%{
      country_iso: "US",
      postcode: "94105",
      place_name: "San Francisco",
      admin1_code: "US.CA"
    })

    :ok
  end

  test "requires the GeoNames list capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/geonames/countries")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/geonames/countries")
  end

  test "renders source-faithful read-only GeoNames indexes and their stable controls", %{conn: conn} do
    grant_capabilities!(["admin.geonames.list"])

    {:ok, countries, _html} = conn |> log_in_as() |> live(~p"/geonames/countries")

    assert has_element?(countries, "#countries-table")
    assert has_element?(countries, "#country-1", "Malaysia")
    assert has_element?(countries, "#countries-sort-population")

    countries
    |> element("#countries-filters")
    |> render_change(%{"filters" => %{"search" => "United", "perPage" => "20"}})

    assert has_element?(countries, "#country-2", "United States")
    refute has_element?(countries, "#country-1", "Malaysia")

    {:ok, admin1, _html} = conn |> log_in_as() |> live(~p"/geonames/admin1")

    assert has_element?(admin1, "#admin1-country-filter")
    assert has_element?(admin1, "#admin1-2", "California")

    admin1
    |> element("#admin1-filters")
    |> render_change(%{"filters" => %{"search" => "", "countryIso" => "MY", "perPage" => "20"}})

    assert has_element?(admin1, "#admin1-1", "Kuala Lumpur")
    refute has_element?(admin1, "#admin1-2", "California")

    {:ok, postcodes, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

    assert has_element?(postcodes, "#postcodes-country-summary")
    assert has_element?(postcodes, "#postcode-country-US", "United States")
    assert has_element?(postcodes, "#postcodes-sort-postcode")

    postcodes
    |> element("#postcodes-filters")
    |> render_change(%{"filters" => %{"search" => "San Francisco", "perPage" => "20"}})

    assert has_element?(postcodes, "#postcode-2", "San Francisco")
    refute has_element?(postcodes, "#postcode-1", "Kuala Lumpur")
  end
end
