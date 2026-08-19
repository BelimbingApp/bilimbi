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
    {:ok, foreign} = Address.create_address(other_scope, %{label: "Other tenant"})
    {:ok, :attached} = Address.attach_to_company(scope, hq.id, 73)

    grant_capabilities!(["admin.address.list", "admin.address.create", "admin.address.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert has_element?(view, "#address-#{hq.id}", "Head Office")
    assert has_element?(view, "#address-#{branch.id}", "Branch")
    refute has_element?(view, "#address-#{foreign.id}")
    assert has_element?(view, "th[aria-sort='ascending'] #addresses-sort-label")
    assert has_element?(view, "#address-create[href='/addresses/create']")
    assert has_element?(view, "#nav-admin-address[aria-current='page']")

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

    assert has_element?(view, "th[aria-sort='ascending'] #addresses-sort-status")
    refute has_element?(view, "th[aria-sort='ascending'] #addresses-sort-label")

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
    assert has_element?(view, "#address-back[href='/addresses']", "Back to addresses")
    assert has_element?(view, "#address-cancel[href='/addresses']", "Cancel")
    assert has_element?(view, "#nav-admin-address[aria-current='page']")
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

  test "an empty list shows no pager at all", %{conn: conn} do
    grant_capabilities!("admin.address.list")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert render(view) =~ "No addresses found."
    refute has_element?(view, "#addresses-pagination")
  end

  test "requires admin.address.view capability to view address show page", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} = Address.create_address(scope, %{label: "HQ"})

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/addresses/#{address.id}")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    grant_capabilities!("admin.address.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")
    assert has_element?(view, "#address-show-page")
  end

  test "redirects to addresses list when address does not exist or belongs to another tenant", %{
    conn: conn,
    other_scope: other_scope
  } do
    {:ok, foreign_address} = Address.create_address(other_scope, %{label: "Foreign HQ"})
    grant_capabilities!("admin.address.view")

    assert {:error,
            {:live_redirect, %{to: "/addresses", flash: %{"error" => "Address not found."}}}} =
             conn |> log_in_as() |> live(~p"/addresses/#{foreign_address.id}")

    assert {:error,
            {:live_redirect, %{to: "/addresses", flash: %{"error" => "Address not found."}}}} =
             conn |> log_in_as() |> live(~p"/addresses/999999")
  end

  test "renders address details, location, provenance, linked entities, and company back link", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} =
      Address.create_address(scope, %{
        label: "Headquarters",
        phone: "+60 3 1234 5678",
        line1: "1 Platform Road",
        line2: "Level 2",
        line3: "Tower B",
        locality: "Kuala Lumpur",
        postcode: "50000",
        country_iso: "MY",
        admin1_code: "MY.14",
        source: "manual_import",
        source_ref: "REF-100",
        parser_version: "v1.2",
        parse_confidence: Decimal.new("0.9500"),
        raw_input: "1 Platform Road, Level 2, 50000 Kuala Lumpur",
        verification_status: "verified"
      })

    {:ok, :attached} =
      Address.attach_to_company(scope, address.id, 73, %{
        kind: ["billing", "shipping"],
        is_primary: true,
        priority: 1
      })

    grant_capabilities!(["admin.address.view", "admin.company.view"])

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/addresses/#{address.id}?company=73")

    assert has_element?(view, "#address-show-page")
    assert has_element?(view, "#address-back-company[href='/companies/73']")
    assert has_element?(view, "#address-back-list[href='/addresses']")
    assert has_element?(view, "#address-view-label", "Headquarters")
    assert has_element?(view, "#address-view-phone", "+60 3 1234 5678")
    assert has_element?(view, "#address-view-lines", "1 Platform Road")
    assert has_element?(view, "#address-view-lines", "Level 2")
    assert has_element?(view, "#address-view-lines", "Tower B")
    assert has_element?(view, "#address-view-country", "Malaysia")
    assert has_element?(view, "#address-view-admin1", "Kuala Lumpur")
    assert has_element?(view, "#address-view-postcode", "50000")
    assert has_element?(view, "#address-view-locality", "Kuala Lumpur")
    assert has_element?(view, "#address-view-source", "manual_import")
    assert has_element?(view, "#address-view-source-ref", "REF-100")
    assert has_element?(view, "#address-view-parser-version", "v1.2")
    assert has_element?(view, "#address-view-parse-confidence", "0.9500")
    assert has_element?(view, "#address-view-raw-input")
    assert has_element?(view, "#linked-company-73")
    assert has_element?(view, "#address-linked-entities-table", "Billing")
    assert has_element?(view, "#address-linked-entities-table", "Shipping")
    assert has_element?(view, "#address-linked-entities-table", "Yes")
  end

  test "allows editing details, location, and provenance when authorized", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} =
      Address.create_address(scope, %{
        label: "Old Label",
        phone: "+60 1",
        line1: "Old Line 1",
        verification_status: "unverified"
      })

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # 1. Edit Details
    view |> element("#address-edit-details-button") |> render_click()
    assert has_element?(view, "#address-details-form")

    view
    |> element("#address-details-form")
    |> render_submit(%{
      "details" => %{
        "label" => "Updated HQ",
        "phone" => "+60 12 3456789",
        "verification_status" => "verified",
        "line1" => "10 Innovation Blvd",
        "line2" => "Suite 300",
        "line3" => ""
      }
    })

    assert render(view) =~ "Address details updated successfully."
    assert has_element?(view, "#address-view-label", "Updated HQ")
    assert has_element?(view, "#address-view-phone", "+60 12 3456789")
    assert has_element?(view, "#address-view-lines", "10 Innovation Blvd")

    # 2. Edit Location with Geonames
    view |> element("#address-edit-location-button") |> render_click()
    assert has_element?(view, "#address-location-form")

    view
    |> element("#address-location-form")
    |> render_change(%{
      "location" => %{
        "country_iso" => "MY",
        "admin1_code" => "",
        "postcode" => "50000",
        "locality" => ""
      }
    })

    assert has_element?(view, "#address-location-admin1 option[value='MY.14'][selected]")
    assert has_element?(view, "#address-location-locality[value='Kuala Lumpur']")

    view
    |> element("#address-location-form")
    |> render_submit(%{
      "location" => %{
        "country_iso" => "MY",
        "admin1_code" => "MY.14",
        "postcode" => "50000",
        "locality" => "Kuala Lumpur"
      }
    })

    assert render(view) =~ "Address location updated successfully."
    assert has_element?(view, "#address-view-locality", "Kuala Lumpur")

    # 3. Edit Provenance
    view |> element("#address-edit-provenance-button") |> render_click()
    assert has_element?(view, "#address-provenance-form")

    view
    |> element("#address-provenance-form")
    |> render_submit(%{
      "provenance" => %{
        "source" => "crm_sync",
        "source_ref" => "CRM-888"
      }
    })

    assert render(view) =~ "Provenance updated successfully."
    assert has_element?(view, "#address-view-source", "crm_sync")
    assert has_element?(view, "#address-view-source-ref", "CRM-888")
  end

  test "supports sorting linked entities column headers", %{conn: conn, scope: scope} do
    {:ok, address} = Address.create_address(scope, %{label: "Shared Hub"})

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Zulu Corp",
      code: "zulu"
    })

    {:ok, :attached} =
      Address.attach_to_company(scope, address.id, 73, %{
        kind: ["billing"],
        is_primary: true,
        priority: 1
      })

    {:ok, :attached} =
      Address.attach_to_company(scope, address.id, 75, %{
        kind: ["shipping"],
        is_primary: false,
        priority: 2
      })

    grant_capabilities!("admin.address.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    assert has_element?(view, "#address-linked-entities-table")

    # Click Sort by Name
    view |> element("#sort-name") |> render_click()

    assert_patch(
      view,
      ~p"/addresses/#{address.id}?#{%{linked_sort_by: "name", linked_sort_dir: "asc"}}"
    )

    # Click Sort by Priority
    view |> element("#sort-priority") |> render_click()

    assert_patch(
      view,
      ~p"/addresses/#{address.id}?#{%{linked_sort_by: "priority", linked_sort_dir: "asc"}}"
    )
  end
end
