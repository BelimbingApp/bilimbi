defmodule Bilimbi.Core.Company.ShowLiveGeonamesDirectTest do
  @moduledoc """
  `core/company` declares `core/geonames`, so show_live must call Geonames
  directly. Probing via `function_exported?` remains for User/Employee/Address
  (#595); this file only tripwires the Geonames path coming back.
  """

  use ExUnit.Case, async: true

  @show_live Path.expand("../lib/company/web/show_live.ex", __DIR__)

  # Geonames public API atoms used by the old probe helpers. Sibling probes for
  # User/Employee/Address use different names, so these refutes stay Geonames-
  # scoped and do not fail on #595's remaining debt.
  @geonames_probe_funs [
    :list_countries,
    :list_admin1,
    :lookup_postcode,
    :search_postcodes,
    :search_city_names
  ]

  test "show_live pins direct Geonames calls and tripwires the old probe form" do
    source = File.read!(@show_live)

    assert source =~ "alias Bilimbi.Core.Geonames"
    assert source =~ "Geonames.list_countries()"
    assert source =~ "Geonames.list_admin1("
    assert source =~ "Geonames.lookup_postcode("
    assert source =~ "Geonames.search_postcodes("
    assert source =~ "Geonames.search_city_names("

    refute source =~ ~r/geonames_mod\b/
    refute source =~ ~r/Module\.concat\(\["Bilimbi", "Core", "Geonames"\]\)/
    refute source =~ ~r/Bilimbi\.Core\.Geonames[^\n]*\n[^\n]*function_exported\?/
    refute source =~ ~r/function_exported\?[^\n]*Bilimbi\.Core\.Geonames/

    for fun <- @geonames_probe_funs do
      refute source =~ ~r/function_exported\?\([^,]+,\s*:#{fun}\b/
    end
  end
end
