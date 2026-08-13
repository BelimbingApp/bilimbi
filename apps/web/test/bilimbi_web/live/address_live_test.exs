defmodule BilimbiWeb.AddressLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    AddressFixtures.create_address_tables!()

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

  test "requires route capabilities", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/addresses")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/addresses")

    grant_capabilities!("admin.address.list")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/addresses/create")
  end

  test "lists, filters, sorts, and safely deletes tenant addresses", %{
    conn: conn,
    scope: scope,
    other_scope: other_scope
  } do
    {:ok, hq} =
      Address.create_address(scope, %{
        label: "Head Office",
        line1: "1 Platform Road",
        locality: "Kuala Lumpur",
        postcode: "50000",
        country_iso: "MY",
        admin1_code: "MY.14",
        verification_status: "verified"
      })

    {:ok, branch} = Address.create_address(scope, %{label: "Branch"})
    {:ok, _foreign} = Address.create_address(other_scope, %{label: "Other tenant"})
    {:ok, :attached} = Address.attach_to_company(scope, hq.id, 73)

    grant_capabilities!(["admin.address.list", "admin.address.create", "admin.address.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert has_element?(view, "#address-#{hq.id}", "Head Office")
    assert has_element?(view, "#address-#{branch.id}", "Branch")
    refute has_element?(view, "#addresses-table", "Other tenant")
    assert has_element?(view, "#address-create[href='/addresses/create']")

    view
    |> element("#addresses-filters")
    |> render_change(%{"filters" => %{"search" => "Head"}})

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Head", page: 1, sortBy: "label", sortDir: "asc"}}"
    )

    assert has_element?(view, "#address-#{hq.id}")
    refute has_element?(view, "#address-#{branch.id}")

    view |> element("#addresses-sort-status") |> render_click()

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Head", page: 1, sortBy: "verification_status", sortDir: "asc"}}"
    )

    view |> element("#address-delete-#{hq.id}") |> render_click()
    assert render(view) =~ "This address is linked. Unlink it before deleting it."
    assert {:ok, _address} = Address.get_address(scope, hq.id)

    view
    |> element("#addresses-filters")
    |> render_change(%{"filters" => %{"search" => ""}})

    view |> element("#address-delete-#{branch.id}") |> render_click()
    refute has_element?(view, "#address-#{branch.id}")
    assert {:error, :address_not_found} = Address.get_address(scope, branch.id)
  end

  test "creates an address with dependent GeoNames suggestions", %{conn: conn, scope: scope} do
    grant_capabilities!(["admin.address.list", "admin.address.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/create")

    assert has_element?(view, "#address-form")
    assert has_element?(view, "#address-country option[value='MY']", "Malaysia")

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
