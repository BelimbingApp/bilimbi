defmodule Bilimbi.Core.Address.CompanyAddressesPanelGeonamesTest do
  @moduledoc """
  The company address panel owns the create-and-attach Geonames cascade that
  moved off the company show page (#595). core/address declares core/geonames,
  so these are direct calls; this tripwires them staying direct rather than
  reverting to the `function_exported?` probe form.
  """

  use ExUnit.Case, async: true

  @panel Path.expand("../lib/address/web/company_addresses_panel.ex", __DIR__)

  @cascade_funs [:list_admin1, :lookup_postcode, :search_postcodes, :search_city_names]

  test "the panel pins its direct Geonames cascade and tripwires the probe form" do
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
