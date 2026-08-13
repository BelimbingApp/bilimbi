defmodule Bilimbi.Core.GeonamesTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Core.Geonames

  import Bilimbi.Core.Geonames.TestFixtures

  setup do
    create_geonames_tables!()
    insert_country!()

    insert_country!(%{
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

    insert_admin1!()
    insert_admin1!(%{code: "MY.05", name: "Negeri Sembilan", geoname_id: 1_733_047})
    insert_admin1!(%{code: "US.CA", name: "California", geoname_id: 5_332_921})
    insert_postcode!()
    insert_city!()

    :ok
  end

  test "lists countries and resolves case-insensitive ISO identity" do
    assert Enum.map(Geonames.list_countries(), & &1.iso) == ["MY", "US"]

    assert country = Geonames.get_country(" my ")
    assert country.country == "Malaysia"
    assert country.currency_code == "MYR"
    assert Geonames.get_country("missing") == nil
  end

  test "returns a source-faithful bounded Countries index page" do
    insert_country!(%{
      iso: "JP",
      iso3: "JPN",
      iso_numeric: "392",
      country: "Japan",
      capital: "Tokyo",
      population: 125_000_000,
      continent: "AS",
      currency_code: "JPY",
      currency_name: "Yen",
      geoname_id: 1_862_730
    })

    page = Geonames.page_countries(%{"search" => "ja", "page_size" => "21"})

    assert page.page == 1
    assert page.page_size == 50
    assert page.total_entries == 1
    assert page.total_pages == 1
    assert [%{iso: "JP", country: "Japan", capital: "Tokyo"}] = page.entries

    assert [%{iso: "JP"} | _rest] = Geonames.page_countries(%{"sortBy" => "population"}).entries

    assert [%{country: "United States"} | _rest] =
             Geonames.page_countries(%{
               "sort_by" => "untrusted column",
               "sort_dir" => "desc"
             }).entries

    assert Geonames.page_countries(%{"page_size" => "1000"}).page_size == 300
  end

  test "lists only administrative divisions owned by the requested country" do
    assert Enum.map(Geonames.list_admin1("my"), &{&1.code, &1.country_iso}) == [
             {"MY.14", "MY"},
             {"MY.05", "MY"}
           ]

    assert Geonames.list_admin1("M") == []
  end

  test "returns global Admin1 pages with country-name search and a bounded country filter" do
    assert [%{code: "US.CA", country_name: "United States"}] =
             Geonames.page_admin1(%{"search" => "united"}).entries

    assert Enum.map(Geonames.admin1_filter_countries(), &{&1.iso, &1.country}) == [
             {"MY", "Malaysia"},
             {"US", "United States"}
           ]

    assert [%{code: "US.CA"}] = Geonames.page_admin1(%{"country_iso" => " us "}).entries
    assert Geonames.page_admin1(%{"country_iso" => "US;DROP"}).entries == []
    assert Geonames.page_admin1(%{"country_iso" => "SG"}).entries == []
  end

  test "looks up postcode localities through the snake-cased public model" do
    assert [postcode] = Geonames.lookup_postcode("my", " 50000 ")
    assert postcode.place_name == "Kuala Lumpur"
    assert postcode.admin1_code == "MY.14"
    assert postcode.latitude == Decimal.new("3.1390000")
    assert Geonames.lookup_postcode("US", "50000") == []
  end

  test "returns searchable postcode pages and independent country summaries" do
    insert_postcode!(%{
      country_iso: "US",
      postcode: "94105",
      place_name: "San Francisco",
      admin1_code: "US.CA"
    })

    insert_postcode!(%{
      country_iso: "US",
      postcode: "10001",
      place_name: "New York",
      admin1_code: "US.NY"
    })

    assert [%{postcode: "94105", country_name: "United States"}] =
             Geonames.page_postcodes(%{"search" => "San Francisco"}).entries

    assert [
             %{country_iso: "US", record_count: 2},
             %{country_iso: "MY", record_count: 1}
           ] = Geonames.list_postcode_country_summaries(%{"sort_by" => "record_count"})

    assert Enum.map(
             Geonames.list_postcode_country_summaries(%{"search" => "no match"}),
             & &1.country_iso
           ) == ["MY", "US"]
  end

  test "resolves a city by durable GeoNames identity" do
    assert city = Geonames.get_city_by_geoname_id(1_735_161)
    assert city.name == "Kuala Lumpur"
    assert city.country_iso == "MY"
    assert city.timezone == "Asia/Kuala_Lumpur"
    assert Geonames.get_city_by_geoname_id(-1) == nil
  end
end
