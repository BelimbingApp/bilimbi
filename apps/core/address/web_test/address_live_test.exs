defmodule BilimbiWeb.AddressLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
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
      ~p"/addresses?#{%{search: "Head", page: 1, perPage: 25, sortBy: "label", sortDir: "asc"}}"
    )

    assert has_element?(view, "#address-#{hq.id}")
    refute has_element?(view, "#address-#{branch.id}")

    view |> element("#addresses-sort-status") |> render_click()

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Head", page: 1, perPage: 25, sortBy: "verification_status", sortDir: "asc"}}"
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

    assert has_element?(
             view,
             "#address-back[href='/addresses'][title='Back to addresses']",
             "Back"
           )

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

  test "an empty list keeps only the rows-per-page control", %{conn: conn} do
    grant_capabilities!("admin.address.list")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert render(view) =~ "No addresses found."
    assert has_element?(view, "#addresses-pagination-page-size")
    refute has_element?(view, "#addresses-pagination-summary")
    refute has_element?(view, "#addresses-pagination-previous")
    refute has_element?(view, "#addresses-pagination-next")
  end

  test "keeps the result count but omits navigation for a single page", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _address} = Address.create_address(scope, %{label: "Head Office"})
    grant_capabilities!("admin.address.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert has_element?(view, "#addresses-pagination-summary", "Showing 1 to 1 of 1 results")
    refute has_element?(view, "#addresses-pagination-previous")
    refute has_element?(view, "#addresses-pagination-next")
    refute render(view) =~ "Page 1 of 1"
  end

  test "paginates and keeps rows per page in URL state", %{conn: conn, scope: scope} do
    for index <- 1..26 do
      label = "Site #{String.pad_leading("#{index}", 2, "0")}"
      {:ok, _address} = Address.create_address(scope, %{label: label})
    end

    grant_capabilities!("admin.address.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    assert has_element?(view, "#addresses-pagination-summary", "Showing 1 to 25 of 26 results")
    assert has_element?(view, "#addresses-pagination-previous[disabled]")
    assert has_element?(view, "#addresses-pagination-next")

    view |> element("#addresses-pagination-next") |> render_click()

    assert has_element?(view, "#addresses-pagination-summary", "Showing 26 to 26 of 26 results")
    assert has_element?(view, "#addresses-pagination-next[disabled]")

    view
    |> form("#addresses-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert has_element?(view, "#addresses-pagination-summary", "Showing 1 to 26 of 26 results")
    refute has_element?(view, "#addresses-pagination-next")

    {:ok, reloaded, _html} = conn |> log_in_as() |> live(~p"/addresses?perPage=50")

    assert has_element?(
             reloaded,
             "#addresses-pagination-summary",
             "Showing 1 to 26 of 26 results"
           )
  end

  test "the search and the rows per page each survive a change to the other", %{
    conn: conn,
    scope: scope
  } do
    {:ok, hq} = Address.create_address(scope, %{label: "Head Office"})
    {:ok, branch} = Address.create_address(scope, %{label: "Branch"})

    grant_capabilities!("admin.address.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")

    view
    |> element("#addresses-filters")
    |> render_change(%{"filters" => %{"search" => "Head"}})

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Head", page: 1, perPage: 25, sortBy: "label", sortDir: "asc"}}"
    )

    view
    |> form("#addresses-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Head", page: 1, perPage: 50, sortBy: "label", sortDir: "asc"}}"
    )

    assert has_element?(view, "#addresses-search[value='Head']")
    assert has_element?(view, "#address-#{hq.id}")
    refute has_element?(view, "#address-#{branch.id}")

    view
    |> element("#addresses-filters")
    |> render_change(%{"filters" => %{"search" => "Branch"}})

    assert_patch(
      view,
      ~p"/addresses?#{%{search: "Branch", page: 1, perPage: 50, sortBy: "label", sortDir: "asc"}}"
    )

    assert has_element?(view, "#addresses-pagination-page-size option[value='50'][selected]")
    assert has_element?(view, "#address-#{branch.id}")
    refute has_element?(view, "#address-#{hq.id}")
  end

  test "a rows-per-page value the list does not offer falls back to 25", %{
    conn: conn,
    scope: scope
  } do
    for index <- 1..26 do
      label = "Site #{String.pad_leading("#{index}", 2, "0")}"
      {:ok, _address} = Address.create_address(scope, %{label: label})
    end

    grant_capabilities!("admin.address.list")

    for per_page <- ["30", "300", "nonsense"] do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses?perPage=#{per_page}")

      assert has_element?(view, "#addresses-pagination-summary", "Showing 1 to 25 of 26 results")
    end
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

  test "renders address facts, location, provenance, linked entities, history and back links", %{
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

    AuditFixtures.create_audit_tables!()

    {:ok, mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: Address.auditable_identity(),
        auditable_id: to_string(address.id),
        subject_name: "Headquarters",
        event: "updated",
        occurred_at: ~N[2026-09-18 09:00:00],
        old_values: %{"label" => "Head Office"},
        new_values: %{"label" => "Headquarters"}
      })

    grant_capabilities!(["admin.address.view", "admin.company.view"])

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/addresses/#{address.id}?company=73")

    assert has_element?(view, "#address-show-page")

    # Back navigation is demoted to plain links reading "← Back".
    assert has_element?(
             view,
             "a#address-back-company[href='/companies/73'][title='Back to company']",
             "Back"
           )

    assert has_element?(
             view,
             "a#address-back-list[href='/addresses'][title='Back to addresses']",
             "Back"
           )

    refute has_element?(view, "#address-back-list", "Back to List")
    refute has_element?(view, "button#address-back-list")

    # Record history is hidden until the actor may list audit logs.
    refute has_element?(view, "#address-record-history-toggle")

    # A viewer sees the facts with no edit affordance.
    assert has_element?(view, "#address-view-label", "Headquarters")
    refute has_element?(view, "#address-label[phx-hook='InlineEdit']")
    refute has_element?(view, "#address-verification-status-display")
    refute has_element?(view, "#address-edit-location-button")
    assert has_element?(view, "#address-view-phone", "+60 3 1234 5678")
    assert has_element?(view, "#address-view-verification-status", "Verified")
    assert has_element?(view, "#address-view-line1", "1 Platform Road")
    assert has_element?(view, "#address-view-line2", "Level 2")
    assert has_element?(view, "#address-view-line3", "Tower B")
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

    grant_capabilities!("admin.audit.log.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # History is a demoted icon action carrying Belimbing's clock, not a button.
    assert has_element?(view, "summary#address-record-history-toggle[title='History']", "History")
    assert has_element?(view, "#address-record-history-toggle .hero-clock")
    refute has_element?(view, "#address-record-history-toggle .hero-clipboard-document-list")

    assert has_element?(
             view,
             "#address-record-history-panel",
             "History for address ##{address.id}"
           )

    assert has_element?(view, "#address-record-history-entry-#{mutation.id}", "Head Office")
    assert has_element?(view, "#address-record-history-entry-#{mutation.id}", "Headquarters")
  end

  test "presents the facts as the shared list without disturbing in-place editing", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} =
      Address.create_address(scope, %{
        label: "Head Office",
        phone: "+60 1",
        verification_status: "verified",
        country_iso: "MY",
        postcode: "50000",
        locality: "Kuala Lumpur"
      })

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # Every section is a named region opened by the one shared heading; no
    # section writes its own h3 or hand-rolled panel.
    for id <- ~w(address-details address-location address-provenance address-linked-entities) do
      assert has_element?(
               view,
               "##{id}-card[role='region'][aria-labelledby='#{id}-heading'] h2##{id}-heading"
             )
    end

    refute has_element?(view, "#address-show-page h3")
    refute has_element?(view, "#address-show-page section")

    # The facts are rows of the shared list; the value cell hosts the editor
    # and, after a commit, the status it reports.
    assert has_element?(view, "#address-details-card dl dt", "Label")

    assert has_element?(
             view,
             "#address-details-card dl dd#address-view-label #address-label[phx-hook='InlineEdit'][data-allow-empty]"
           )

    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "Updated HQ"})

    assert has_element?(
             view,
             "dd#address-view-label #address-label-status[role='status']",
             "Saved"
           )

    assert has_element?(
             view,
             "dd#address-view-label #address-label [data-role='text']",
             "Updated HQ"
           )

    # The choice fact keeps its trigger and status in its own row.
    assert has_element?(
             view,
             "dd#address-view-verification-status button#address-verification-status-display",
             "Verified"
           )

    view |> element("#address-verification-status-display") |> render_click()

    view
    |> form("#address-verification-status-form", %{"verification_status" => "suggested"})
    |> render_change()

    assert has_element?(
             view,
             "dd#address-view-verification-status #address-verification-status-status[role='status']",
             "Saved"
           )

    # The grouped location editor opens from the demoted icon beside its
    # heading and replaces the list while it is open.
    assert has_element?(view, "h2#address-location-heading + button#address-edit-location-button")
    assert has_element?(view, "#address-location-card dl dd#address-view-postcode", "50000")

    view |> element("#address-edit-location-button") |> render_click()

    assert has_element?(view, "#address-location-form")
    refute has_element?(view, "#address-location-card dl")

    view |> element("#address-cancel-location") |> render_click()

    assert has_element?(
             view,
             "#address-location-card dl dd#address-view-locality",
             "Kuala Lumpur"
           )

    # Provenance facts are rows of the same list shape.
    assert has_element?(
             view,
             "#address-provenance-card dl dd#address-view-source-ref #address-source-ref[phx-hook='InlineEdit']"
           )

    refute has_element?(view, "#address-provenance-card dd#address-view-raw-input")
  end

  test "shows an in-place save in the record history panel", %{conn: conn, scope: scope} do
    {:ok, address} = Address.create_address(scope, %{label: "Head Office"})

    AuditFixtures.create_audit_tables!()

    grant_capabilities!([
      "admin.address.view",
      "admin.address.update",
      "admin.audit.log.list"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "Headquarters"})
    assert has_element?(view, "#address-label-status[role='status']", "Saved")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    refute has_element?(view, "#address-record-history-empty")
    assert has_element?(view, "#address-record-history-panel", "Head Office")
    assert has_element?(view, "#address-record-history-panel", "Headquarters")
  end

  test "saves each committed text fact in place and reports the outcome on that fact", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} =
      Address.create_address(scope, %{
        label: "Old Label",
        phone: "+60 1",
        line1: "Old Line 1",
        line2: "Old Line 2",
        verification_status: "unverified"
      })

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # Every text fact is an in-place editor; there is no edit mode and no save button.
    for id <-
          ~w(address-label address-phone address-line1 address-line2 address-line3 address-source address-source-ref) do
      assert has_element?(
               view,
               "##{id}[phx-hook='InlineEdit'][data-save-event='save_field'][data-allow-empty]"
             )
    end

    refute has_element?(view, "#address-edit-details-button")
    refute has_element?(view, "#address-save-details")
    refute has_element?(view, "#address-details-form")
    refute has_element?(view, "#address-provenance-form")

    # A committed edit saves by itself and the fact reports "Saved".
    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "  Updated HQ  "})

    assert has_element?(view, "#address-view-label", "Updated HQ")
    assert has_element?(view, "#address-label-status[role='status']", "Saved")
    assert page_title(view) == "Updated HQ"
    assert {:ok, %{label: "Updated HQ"}} = Address.get_address(scope, address.id)

    # Clearing a nullable fact is a real edit.
    render_hook(view, "save_field", %{"id" => to_string(address.id), "line2" => ""})

    assert has_element?(view, "#address-line2-status[role='status']", "Saved")
    refute has_element?(view, "#address-label-status")
    assert has_element?(view, "#address-line2 [data-role='text']", "—")
    assert {:ok, %{line2: nil}} = Address.get_address(scope, address.id)

    # Provenance facts follow the same rule.
    render_hook(view, "save_field", %{"id" => to_string(address.id), "source_ref" => "CRM-888"})

    assert has_element?(view, "#address-view-source-ref", "CRM-888")
    assert has_element?(view, "#address-source-ref-status", "Saved")

    # A field the page does not edit in place is ignored, not written.
    render_hook(view, "save_field", %{"id" => to_string(address.id), "postcode" => "99999"})
    assert {:ok, %{postcode: nil}} = Address.get_address(scope, address.id)
  end

  test "a refused commit keeps the stored value on screen and reports the reason on the fact", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} = Address.create_address(scope, %{label: "HQ", phone: "+60 1"})

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    too_long = String.duplicate("x", 256)
    render_hook(view, "save_field", %{"id" => to_string(address.id), "phone" => too_long})

    assert has_element?(view, "#address-phone-status[role='alert']", "was not saved")
    assert has_element?(view, "#address-phone-status", "Phone should be at most 255 character(s)")
    assert has_element?(view, "#address-phone-status", String.slice(too_long, 0, 40))
    assert has_element?(view, "#address-view-phone", "+60 1")
    refute has_element?(view, "#address-phone-status", "Saved")
    refute has_element?(view, "#flash-group", "was not saved")
    assert {:ok, %{phone: "+60 1"}} = Address.get_address(scope, address.id)

    # The alert stays until that fact is committed again, and then gives way
    # to the new outcome; a success elsewhere does not clear it.
    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "New HQ"})
    assert has_element?(view, "#address-phone-status[role='alert']")
    assert has_element?(view, "#address-label-status", "Saved")

    render_hook(view, "save_field", %{"id" => to_string(address.id), "phone" => "+60 2"})
    refute has_element?(view, "#address-phone-status[role='alert']")
    assert has_element?(view, "#address-phone-status", "Saved")
    assert has_element?(view, "#address-view-phone", "+60 2")
  end

  test "commits the verification status on change and the location group on apply", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} =
      Address.create_address(scope, %{label: "HQ", verification_status: "unverified"})

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # Choice fact: the badge is the trigger, the select commits on change.
    assert has_element?(view, "#address-verification-status-display", "Unverified")
    refute has_element?(view, "#address-verification-status-form")

    view |> element("#address-verification-status-display") |> render_click()

    assert has_element?(
             view,
             "#address-verification-status-form select#address-verification-status"
           )

    view
    |> element("#address-verification-status-form")
    |> render_change(%{"verification_status" => "verified"})

    refute has_element?(view, "#address-verification-status-form")
    assert has_element?(view, "#address-verification-status-display", "Verified")
    assert has_element?(view, "#address-verification-status-status[role='status']", "Saved")
    assert {:ok, %{verification_status: "verified"}} = Address.get_address(scope, address.id)

    # Escape or leaving the select cancels without writing.
    view |> element("#address-verification-status-display") |> render_click()
    render_hook(view, "cancel_edit_field", %{})
    refute has_element?(view, "#address-verification-status-form")
    assert {:ok, %{verification_status: "verified"}} = Address.get_address(scope, address.id)

    # Location facts depend on one another, so they commit together from a
    # demoted icon action, with GeoNames suggestions while editing.
    assert has_element?(view, "button#address-edit-location-button[aria-label='Edit location']")
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

    refute has_element?(view, "#address-location-form")
    assert has_element?(view, "#address-location-status[role='status']", "Saved")
    assert has_element?(view, "#address-view-locality", "Kuala Lumpur")
    assert has_element?(view, "#address-view-country", "Malaysia")

    # A refused group keeps the editor open with the error on its field.
    view |> element("#address-edit-location-button") |> render_click()

    view
    |> element("#address-location-form")
    |> render_submit(%{
      "location" => %{
        "country_iso" => "MY",
        "admin1_code" => "MY.14",
        "postcode" => String.duplicate("9", 256),
        "locality" => "Kuala Lumpur"
      }
    })

    assert has_element?(view, "#address-location-form")

    assert has_element?(
             view,
             "#address-location-postcode-error-0",
             "should be at most 255 character(s)"
           )

    refute has_element?(view, "#address-location-status[role='status']")
    assert {:ok, %{postcode: "50000"}} = Address.get_address(scope, address.id)
  end

  test "refuses in-place writes once the update capability is gone", %{conn: conn, scope: scope} do
    {:ok, address} =
      Address.create_address(scope, %{label: "HQ", verification_status: "unverified"})

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")

    # A commit that did land, so the refusal below has a stale "Saved" to clear.
    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "HQ North"})
    assert has_element?(view, "#address-label-status[role='status']", "Saved")

    grant =
      Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.address.update"))

    assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "Forged"})
    assert has_element?(view, "#flash-group", "You do not have permission to update addresses.")

    # The refusal is the whole outcome: no "Saved" from the earlier commit
    # stands beside it.
    refute has_element?(view, "#address-label-status")

    render_hook(view, "save_verification_status", %{"verification_status" => "verified"})

    render_hook(view, "save_location", %{
      "location" => %{
        "country_iso" => "MY",
        "admin1_code" => "",
        "postcode" => "",
        "locality" => ""
      }
    })

    assert {:ok, %{label: "HQ North", verification_status: "unverified", country_iso: nil}} =
             Address.get_address(scope, address.id)
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
