defmodule Bilimbi.Core.Address.CompanyAddressesPanelGeonamesTest do
  @moduledoc """
  The create-and-attach Geonames cascade lives in `LocationSuggestion`.
  core/address declares core/geonames, so these are direct calls; this
  tripwires them staying direct rather than reverting to the
  `function_exported?` probe form.
  """

  use ExUnit.Case, async: true

  @panel Path.expand("../lib/address/location_suggestion.ex", __DIR__)

  @cascade_funs [:list_admin1, :lookup_postcode, :search_postcodes, :search_city_names]

  test "location suggestions pin direct Geonames calls and tripwire the probe form" do
    source = File.read!(@panel)

    assert source =~ "alias Bilimbi.Core.Geonames"
    assert source =~ "Geonames.list_admin1("
    assert source =~ "Geonames.lookup_postcode("
    assert source =~ "Geonames.search_postcodes("
    assert source =~ "Geonames.search_city_names("

    refute source =~ ~r/geonames_mod\b/
    refute source =~ ~r/Module\.concat\(\["Bilimbi", "Core", "Geonames"\]\)/

    for fun <- @cascade_funs do
      refute source =~ ~r/function_exported\?\([^,]+,\s*:#{fun}\b/
    end
  end
end
