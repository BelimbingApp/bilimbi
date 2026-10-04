defmodule BilimbiWeb.AddressIndexLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
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

  test "requires route capabilities", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/addresses")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/addresses")

    grant_capabilities!("admin.address.list")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/addresses/create")
  end

  test "the API refuses address deletion without its capability", %{scope: scope} do
    user_scope = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 91, 73)
    {:ok, address} = Address.create_address(scope, %{label: "Protected"})

    assert {:error, :forbidden} = Address.delete_address(user_scope, address.id)

    grant_capabilities!("admin.address.delete")
    assert :ok = Address.delete_address(user_scope, address.id)
  end

  test "refuses a deletion request when permission is revoked after mount", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} = Address.create_address(scope, %{label: "Protected"})
    grant_capabilities!(["admin.address.list", "admin.address.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")
    assert has_element?(view, "#address-delete-#{address.id}")

    grant =
      Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.address.delete"))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)

    view |> element("#address-delete-#{address.id}") |> render_click()

    assert has_element?(view, "#flash-error", "You do not have permission to delete addresses.")
    refute has_element?(view, "#delete-address-confirm")
    assert has_element?(view, "#address-#{address.id}")
    assert {:ok, ^address} = Address.get_address(scope, address.id)
  end

  test "refuses deletion when permission is revoked after opening confirmation", %{
    conn: conn,
    scope: scope
  } do
    {:ok, address} = Address.create_address(scope, %{label: "Protected"})
    grant_capabilities!(["admin.address.list", "admin.address.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/addresses")
    view |> element("#address-delete-#{address.id}") |> render_click()
    assert has_element?(view, "#delete-address-confirm-confirm")

    grant =
      Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.address.delete"))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)

    view |> element("#delete-address-confirm-confirm") |> render_click()

    assert has_element?(view, "#flash-error", "You do not have permission to delete addresses.")
    refute has_element?(view, "#flash-success")
    assert has_element?(view, "#address-#{address.id}")
    assert {:ok, ^address} = Address.get_address(scope, address.id)
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

    # Deleting confirms through the shared dialog, which names the address and
    # says what cannot be undone; no native confirm remains. A linked address
    # is refused after confirming: the dialog closes and the flash says where
    # to unlink it.
    refute has_element?(view, "#address-delete-#{hq.id}[data-confirm]")
    view |> element("#address-delete-#{hq.id}") |> render_click()

    assert_modal_dialog(view, "delete-address-confirm", "“Head Office” will be deleted.")
    assert has_element?(view, "dialog#delete-address-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#delete-address-confirm-description",
             "It can no longer be attached to a company or employee. This cannot be undone."
           )

    view |> element("#delete-address-confirm-confirm", "Delete") |> render_click()
    refute has_element?(view, "#delete-address-confirm")

    assert has_element?(
             view,
             "#flash-error",
             "“Head Office” was not deleted: it is still attached to a company or employee. Unlink it there first."
           )

    assert {:ok, _address} = Address.get_address(scope, hq.id)

    view
    |> element("#addresses-filters")
    |> render_change(%{"filters" => %{"search" => ""}})

    # Cancelling keeps the address.
    view |> element("#address-delete-#{branch.id}") |> render_click()
    view |> element("#delete-address-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#delete-address-confirm")
    assert has_element?(view, "#address-#{branch.id}")

    # Confirming deletes it and reports the completed write as a success.
    view |> element("#address-delete-#{branch.id}") |> render_click()

    assert has_element?(
             view,
             "#delete-address-confirm-confirm[phx-disable-with='Deleting…']",
             "Delete"
           )

    view |> element("#delete-address-confirm-confirm") |> render_click()
    refute has_element?(view, "#delete-address-confirm")
    assert has_element?(view, "#flash-success", "Address deleted.")
    refute has_element?(view, "#address-#{branch.id}")
    assert {:error, :address_not_found} = Address.get_address(scope, branch.id)
  end

  test "a snake_case sort query leaves the address list on its default sort", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _hq} = Address.create_address(scope, %{label: "Head Office"})
    grant_capabilities!("admin.address.list")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/addresses?#{%{"sort_by" => "verification_status", "sort_dir" => "desc"}}")

    assert has_element?(view, "th[aria-sort='ascending'] #addresses-sort-label")
    refute has_element?(view, "th[aria-sort='ascending'] #addresses-sort-status")
    refute has_element?(view, "th[aria-sort='descending'] #addresses-sort-status")
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
end
