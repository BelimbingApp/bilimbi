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
      iso: "AA",
      iso3: "AAA",
      iso_numeric: "001",
      country: "Timed Tie A",
      capital: "Alpha",
      population: 10,
      continent: "EU",
      currency_code: "AAA",
      currency_name: "Alpha",
      geoname_id: 1_000_001,
      updated_at: ~N[2024-01-01 00:00:00]
    })

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

    insert_country!(%{
      iso: "ZZ",
      iso3: "ZZZ",
      iso_numeric: "999",
      country: "Timed Tie Z",
      capital: "Zulu",
      population: 10,
      continent: "EU",
      currency_code: "ZZZ",
      currency_name: "Zulu",
      geoname_id: 1_000_002,
      updated_at: ~N[2025-01-01 00:00:00]
    })

    page = Geonames.page_countries(%{"search" => "jp", "page_size" => "21"})

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

    assert Enum.map(
             Geonames.page_countries(%{"search" => "Timed", "sortBy" => "population"}).entries,
             & &1.iso
           ) == ["AA", "ZZ"]

    assert Enum.map(
             Geonames.page_countries(%{"search" => "Timed", "sortBy" => "updated_at"}).entries,
             & &1.iso
           ) == ["ZZ", "AA"]

    assert %{page: 1, page_size: 300} =
             Geonames.page_countries(%{"page" => "0", "page_size" => "1000"})

    assert %{page: 9, total_pages: 1, entries: []} =
             Geonames.page_countries(%{"search" => "Japan", "page" => "9"})
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

    assert [%{code: "MY.05"}] = Geonames.page_admin1(%{"search" => "MY.05"}).entries
    assert [%{code: "US.CA"}] = Geonames.page_admin1(%{"search" => "California"}).entries

    assert Enum.map(Geonames.admin1_filter_countries(), &{&1.iso, &1.country}) == [
             {"MY", "Malaysia"},
             {"US", "United States"}
           ]

    assert [%{code: "US.CA"}] = Geonames.page_admin1(%{"country_iso" => " us "}).entries
    assert Geonames.page_admin1(%{"country_iso" => "US;DROP"}).entries == []
    assert Geonames.page_admin1(%{"country_iso" => "%_"}).entries == []
    assert Geonames.page_admin1(%{"country_iso" => "SG"}).entries == []
  end

  test "orders Admin1 source fields deterministically" do
    insert_admin1!(%{
      code: "US.TA",
      name: "Timed Tie",
      geoname_id: 5_330_001,
      updated_at: ~N[2024-01-01 00:00:00]
    })

    insert_admin1!(%{
      code: "US.TB",
      name: "Timed Tie",
      geoname_id: 5_330_002,
      updated_at: ~N[2025-01-01 00:00:00]
    })

    assert Enum.map(
             Geonames.page_admin1(%{"search" => "Timed", "sortBy" => "updated_at"}).entries,
             & &1.code
           ) == ["US.TB", "US.TA"]

    assert Enum.map(
             Geonames.page_admin1(%{"search" => "Timed", "sortBy" => "name"}).entries,
             & &1.code
           ) == ["US.TB", "US.TA"]
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

    assert [%{postcode: "94105"}] = Geonames.page_postcodes(%{"search" => "941"}).entries

    assert [%{postcode: "94105", country_name: "United States"}] =
             Geonames.page_postcodes(%{"search" => "San Francisco"}).entries

    assert Enum.map(Geonames.page_postcodes(%{"search" => "us"}).entries, &(&1.postcode)) ==
             [
               "10001",
               "94105"
             ]

    assert Enum.map(
             Geonames.page_postcodes(%{"search" => "United"}).entries,
             &(&1.postcode)
           ) == [
             "10001",
             "94105"
           ]

    insert_country!(%{
      iso: "JP",
      iso3: "JPN",
      iso_numeric: "392",
      country: "Japan",
      capital: "Tokyo",
      continent: "AS",
      currency_code: "JPY",
      currency_name: "Yen",
      geoname_id: 1_862_730
    })

    insert_postcode!(%{
      country_iso: "JP",
      postcode: "100-0001",
      place_name: "Tokyo",
      admin1_code: "JP.13"
    })

    assert [
             %{country_iso: "US", record_count: 2},
             %{country_iso: "JP", record_count: 1},
             %{country_iso: "MY", record_count: 1}
           ] = Geonames.list_postcode_country_summaries(%{"sort_by" => "record_count"})

    assert Enum.map(
             Geonames.list_postcode_country_summaries(%{"search" => "no match"}),
             & &1.country_iso
           ) == ["JP", "MY", "US"]
  end

  test "orders postcode ties and preserves empty-page and summary defaults" do
    insert_postcode!(%{
      country_iso: "US",
      postcode: "10001",
      place_name: "Timed Tie",
      admin1_code: "US.NY",
      updated_at: ~N[2024-01-01 00:00:00]
    })

    insert_postcode!(%{
      country_iso: "US",
      postcode: "94105",
      place_name: "Timed Tie",
      admin1_code: "US.CA",
      updated_at: ~N[2025-01-01 00:00:00]
    })

    assert Enum.map(
             Geonames.page_postcodes(%{"search" => "Timed", "sortBy" => "updated_at"}).entries,
             & &1.postcode
           ) == ["94105", "10001"]

    assert Enum.map(
             Geonames.page_postcodes(%{"search" => "Timed", "sortBy" => "place_name"}).entries,
             & &1.postcode
           ) == ["94105", "10001"]

    assert %{page: 9, total_pages: 1, entries: []} =
             Geonames.page_postcodes(%{"search" => "Timed", "page" => "9"})

    assert Enum.map(Geonames.list_postcode_country_summaries(), & &1.country_iso) == ["MY", "US"]

    assert Enum.map(
             Geonames.list_postcode_country_summaries(%{"sortBy" => "record_count"}),
             & &1.country_iso
           ) == ["US", "MY"]
  end

  test "resolves a city by durable GeoNames identity" do
    assert city = Geonames.get_city_by_geoname_id(1_735_161)
    assert city.name == "Kuala Lumpur"
    assert city.country_iso == "MY"
    assert city.timezone == "Asia/Kuala_Lumpur"
    assert Geonames.get_city_by_geoname_id(-1) == nil
  end
end
