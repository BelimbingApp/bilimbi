defmodule Bilimbi.Core.Address.CompanyAddressesPanelGeonamesTest do
  @moduledoc """
  The create page, the address detail editor, and the company panel ask
  `LocationSuggestion` for the same postcode cascade.
  """

  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Core.Address.LocationSuggestion

  import Bilimbi.Core.Geonames.TestFixtures

  setup do
    create_geonames_tables!()
    insert_country!()
    insert_admin1!()
    insert_postcode!()
    :ok
  end

  test "a changed postcode fills the division and the single matching locality" do
    previous = blank_location("MY")

    assert {params, auto} =
             LocationSuggestion.suggest(
               %{previous | "postcode" => "50000"},
               previous,
               %{admin1_code: false, locality: false}
             )

    assert params["country_iso"] == "MY"
    assert params["admin1_code"] == "MY.14"
    assert params["postcode"] == "50000"
    assert params["locality"] == "Kuala Lumpur"
    assert auto == %{admin1_code: true, locality: true}
  end

  test "several localities for one postcode fill the division and leave the locality" do
    insert_postcode!(%{place_name: "Chow Kit"})
    previous = %{blank_location("MY") | "locality" => "Typed"}

    assert {params, auto} =
             LocationSuggestion.suggest(
               %{previous | "postcode" => "50000"},
               previous,
               %{admin1_code: false, locality: false}
             )

    assert params["admin1_code"] == "MY.14"
    assert params["postcode"] == "50000"
    assert params["locality"] == "Typed"
    assert auto == %{admin1_code: true, locality: false}
  end

  test "option lists follow the country, postcode, and locality" do
    insert_city!(%{
      geoname_id: 1_735_162,
      name: "Petaling",
      ascii_name: "Petaling",
      admin1_code: "14",
      population: 100
    })

    options =
      LocationSuggestion.options(%{
        "country_iso" => "my",
        "admin1_code" => "MY.14",
        "postcode" => "50000",
        "locality" => "Pet"
      })

    assert options.admin1 == [{"Kuala Lumpur", "MY.14"}]
    assert options.postcodes == ["50000"]
    assert options.localities == ["Kuala Lumpur", "Petaling"]
  end

  test "a country change clears division, postcode, and locality" do
    previous = %{
      "country_iso" => "MY",
      "admin1_code" => "MY.14",
      "postcode" => "50000",
      "locality" => "Kuala Lumpur"
    }

    incoming = %{previous | "country_iso" => "sg", "postcode" => "018989"}

    assert {params, auto} =
             LocationSuggestion.suggest(incoming, previous, %{
               admin1_code: true,
               locality: true
             })

    assert params["country_iso"] == "SG"
    assert params["admin1_code"] == ""
    assert params["postcode"] == ""
    assert params["locality"] == ""
    assert auto == %{admin1_code: false, locality: false}
  end

  defp blank_location(country_iso) do
    %{"country_iso" => country_iso, "admin1_code" => "", "postcode" => "", "locality" => ""}
  end
end
