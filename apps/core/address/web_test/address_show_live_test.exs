defmodule BilimbiWeb.AddressShowLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
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

    # History is a demoted labelled disclosure carrying Belimbing's clock.
    assert has_element?(
             view,
             "button#address-record-history-toggle[title='History'][aria-expanded='false']",
             "History"
           )

    assert has_element?(view, "#address-record-history-toggle .hero-clock")
    refute has_element?(view, "#address-record-history-toggle .hero-clipboard-document-list")
    refute has_element?(view, "summary#address-record-history-toggle")

    view |> element("#address-record-history-toggle") |> render_click()

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

    grant_capabilities!([
      "admin.address.view",
      "admin.address.update",
      "admin.audit.log.list"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")
    view |> element("#address-record-history-toggle") |> render_click()
    refute has_element?(view, "#address-record-history-panel", "Headquarters")

    render_hook(view, "save_field", %{"id" => to_string(address.id), "label" => "Headquarters"})
    assert has_element?(view, "#address-label-status[role='status']", "Saved")

    # On the same view: the open trail follows the edit without a remount.
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
             "#address-verification-status-form select#address-verification-status-select"
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
        "locality" => "Kuala Lumpur"
      }
    })

    assert has_element?(view, "#address-location-admin1 option[value='MY.14']")
    refute has_element?(view, "#address-location-admin1 option[value='MY.14'][selected]")
    refute has_element?(view, "#address-location-postcode[value='50000']")
    refute has_element?(view, "#address-location-locality[value='Kuala Lumpur']")

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

  test "loads location suggestions when the editor opens", %{conn: conn, scope: scope} do
    {:ok, address} =
      Address.create_address(scope, %{
        label: "HQ",
        country_iso: "MY",
        admin1_code: "MY.14",
        postcode: "50000",
        locality: "Kuala Lumpur"
      })

    grant_capabilities!(["admin.address.view", "admin.address.update"])

    {mount_queries, view} =
      capture_queries(fn ->
        {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses/#{address.id}")
        assert has_element?(view, "#address-view-postcode", "50000")
        refute has_element?(view, "#address-location-form")
        view
      end)

    refute Enum.any?(mount_queries, &suggestion_query?/1)

    {open_queries, _} =
      capture_queries(fn ->
        view |> element("#address-edit-location-button") |> render_click()

        assert has_element?(view, "#address-location-form")
        assert has_element?(view, "#address-location-admin1 option[value='MY.14']")
        assert has_element?(view, "#address-location-postcode-options option[value='50000']")

        assert has_element?(
                 view,
                 "#address-location-locality-options option[value='Kuala Lumpur']"
               )
      end)

    assert Enum.any?(open_queries, &suggestion_query?/1)

    {cancel_queries, _} =
      capture_queries(fn ->
        view |> element("#address-cancel-location") |> render_click()
        refute has_element?(view, "#address-location-form")
        assert has_element?(view, "#address-view-locality", "Kuala Lumpur")
      end)

    refute Enum.any?(cancel_queries, &suggestion_query?/1)

    view |> element("#address-edit-location-button") |> render_click()

    {save_queries, _} =
      capture_queries(fn ->
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
      end)

    refute Enum.any?(save_queries, &suggestion_query?/1)
  end

  defp capture_queries(fun) do
    handler = "address-location-queries-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _, _, %{query: query}, _ -> send(parent, {:address_location_query, handler, query}) end,
      nil
    )

    try do
      result = fun.()
      {flush_queries(handler, []), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp suggestion_query?(query) do
    String.contains?(query, "geonames_postcodes") or String.contains?(query, "geonames_cities")
  end

  defp flush_queries(handler, queries) do
    receive do
      {:address_location_query, ^handler, query} -> flush_queries(handler, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end
end
