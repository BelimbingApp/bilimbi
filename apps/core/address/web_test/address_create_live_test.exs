defmodule BilimbiWeb.AddressCreateLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 42, code: "other"})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    GeonamesFixtures.insert_country!()
    GeonamesFixtures.insert_admin1!()

    GeonamesFixtures.insert_postcode!(%{
      postcode: "50000",
      place_name: "Kuala Lumpur",
      admin1_code: "14"
    })

    {:ok, scope} = Tenancy.scope(41)
    {:ok, other_scope} = Tenancy.scope(42)

    %{scope: scope, other_scope: other_scope}
  end

  test "creates an address with dependent GeoNames suggestions", %{conn: conn, scope: scope} do
    grant_capabilities!(["admin.address.list", "admin.address.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/create")

    assert has_element?(view, "#address-form")

    assert has_element?(
             view,
             "#address-back[href='/addresses'][title='Back to addresses']",
             "Back"
           )

    assert has_element?(view, "#address-cancel[href='/addresses']", "Cancel")
    assert has_element?(view, "#nav-admin-address[aria-current='page']")
    assert has_element?(view, "#address-country[role='combobox']")
    assert Geonames.country_options() == [{"Malaysia (MY)", "MY"}]

    assert has_element?(
             view,
             "#address-country-option-MY[role='option'][data-value='MY'][data-label='Malaysia (MY)']",
             "Malaysia (MY)"
           )

    assert has_element?(view, "#address-country-value[name='address[country_iso]'][value='']")

    view
    |> element("#address-form")
    |> render_change(%{
      "address" => %{
        "label" => "New HQ",
        "phone" => "",
        "line1" => "8 Market Street",
        "line2" => "",
        "line3" => "",
        "country_iso" => "MY",
        "admin1_code" => "",
        "postcode" => "",
        "locality" => "",
        "source" => "manual",
        "source_ref" => "",
        "parser_version" => "",
        "parse_confidence" => "",
        "verification_status" => "unverified",
        "raw_input" => ""
      }
    })

    assert has_element?(view, "#address-admin1 option[value='MY.14']", "Kuala Lumpur")
    refute has_element?(view, "#address-admin1 option[value='MY.14']", "Kuala Lumpur (MY.14)")

    view
    |> element("#address-form")
    |> render_change(%{
      "address" => %{
        "label" => "New HQ",
        "phone" => "",
        "line1" => "8 Market Street",
        "line2" => "",
        "line3" => "",
        "country_iso" => "MY",
        "admin1_code" => "",
        "postcode" => "50000",
        "locality" => "",
        "source" => "manual",
        "source_ref" => "",
        "parser_version" => "",
        "parse_confidence" => "",
        "verification_status" => "unverified",
        "raw_input" => ""
      }
    })

    assert has_element?(view, "#address-admin1 option[value='MY.14'][selected]")
    assert has_element?(view, "#address-locality[value='Kuala Lumpur']")
    assert has_element?(view, "#address-admin1-auto")
    assert has_element?(view, "#address-locality-auto")

    view |> element("#address-form") |> render_submit()

    assert_redirect(view, ~p"/addresses")

    assert {:ok, [address]} = Address.list_addresses(scope)
    assert address.label == "New HQ"
    assert address.country_iso == "MY"
    assert address.admin1_code == "MY.14"
    assert address.postcode == "50000"
    assert address.locality == "Kuala Lumpur"
  end
end
