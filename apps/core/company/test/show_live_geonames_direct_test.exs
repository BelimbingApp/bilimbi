defmodule Bilimbi.Core.Company.ShowLiveGeonamesDirectTest do
  @moduledoc """
  `core/company` declares `core/geonames`, so show_live must call Geonames
  directly. Probing via `function_exported?` is the debt tracked in #595 for
  User/Employee/Address only.
  """

  use ExUnit.Case, async: true

  @show_live Path.expand("../lib/company/web/show_live.ex", __DIR__)

  test "show_live calls Geonames directly and does not probe it" do
    source = File.read!(@show_live)

    assert source =~ "alias Bilimbi.Core.Geonames"
    assert source =~ "Geonames.list_countries()"
    assert source =~ "Geonames.list_admin1("
    assert source =~ "Geonames.lookup_postcode("
    assert source =~ "Geonames.search_postcodes("
    assert source =~ "Geonames.search_city_names("

    refute source =~ ~r/geonames_mod\b/
    refute source =~ ~r/Module\.concat\(\["Bilimbi", "Core", "Geonames"\]\)/
  end
end
