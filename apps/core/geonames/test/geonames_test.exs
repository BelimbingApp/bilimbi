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

  test "lists only administrative divisions owned by the requested country" do
    assert Enum.map(Geonames.list_admin1("my"), &{&1.code, &1.country_iso}) == [
             {"MY.14", "MY"},
             {"MY.05", "MY"}
           ]

    assert Geonames.list_admin1("M") == []
  end

  test "looks up postcode localities through the snake-cased public model" do
    assert [postcode] = Geonames.lookup_postcode("my", " 50000 ")
    assert postcode.place_name == "Kuala Lumpur"
    assert postcode.admin1_code == "MY.14"
    assert postcode.latitude == Decimal.new("3.1390000")
    assert Geonames.lookup_postcode("US", "50000") == []
  end

  test "resolves a city by durable GeoNames identity" do
    assert city = Geonames.get_city_by_geoname_id(1_735_161)
    assert city.name == "Kuala Lumpur"
    assert city.country_iso == "MY"
    assert city.timezone == "Asia/Kuala_Lumpur"
    assert Geonames.get_city_by_geoname_id(-1) == nil
  end
end
