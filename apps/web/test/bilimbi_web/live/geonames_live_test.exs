defmodule BilimbiWeb.GeonamesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.Geonames.Web.CountriesLive
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    GeonamesFixtures.insert_country!(%{updated_at: ~N[2026-07-24 12:34:56]})

    GeonamesFixtures.insert_country!(%{
      iso: "US",
      iso3: "USA",
      iso_numeric: "840",
      country: "United States",
      capital: "Washington",
      continent: "NA",
      currency_code: "USD",
      currency_name: "Dollar",
      geoname_id: 6_252_001
    })

    GeonamesFixtures.insert_admin1!()
    GeonamesFixtures.insert_admin1!(%{code: "US.CA", name: "California", geoname_id: 5_332_921})
    GeonamesFixtures.insert_postcode!()

    GeonamesFixtures.insert_postcode!(%{
      country_iso: "US",
      postcode: "94105",
      place_name: "San Francisco",
      admin1_code: "US.CA"
    })

    :ok
  end

  test "requires the GeoNames list capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/geonames/countries")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/geonames/countries")
  end

  test "renders source-faithful read-only GeoNames indexes and their stable controls", %{
    conn: conn
  } do
    grant_capabilities!(["admin.geonames.list"])

    {:ok, countries, _html} = conn |> log_in_as() |> live(~p"/geonames/countries")

    assert has_element?(countries, "#countries-table")
    assert has_element?(countries, "#country-1", "Malaysia")

    assert has_element?(
             countries,
             "#countries-search[placeholder='Search by country name or ISO code...']"
           )

    assert has_element?(countries, "#countries-sort-population")
    assert has_element?(countries, "caption.sr-only", "Countries")
    assert has_element?(countries, "th.text-right #countries-sort-population")
    assert has_element?(countries, "#countries-pagination-page-size option[value='25'][selected]")
    assert has_element?(countries, "#countries-pin[data-nav-pin='nav-admin-geonames-country']")
    assert has_element?(countries, "#countries-update[phx-click='update-countries']", "Update")

    assert has_element?(
             countries,
             "#country-1-updated[phx-hook='DateTime'][datetime='2026-07-24T12:34:56Z']",
             "24/07/2026 UTC"
           )

    countries
    |> element("#countries-filters")
    |> render_change(%{"filters" => %{"search" => "United"}})

    assert has_element?(countries, "#country-2", "United States")
    refute has_element?(countries, "#country-1", "Malaysia")

    {:ok, admin1, _html} = conn |> log_in_as() |> live(~p"/geonames/admin1")

    assert has_element?(admin1, "#admin1-table")
    assert has_element?(admin1, "caption.sr-only", "Admin1 divisions")
    assert has_element?(admin1, "#admin1-country-filter")
    assert has_element?(admin1, "label[for='admin1-country-filter'].sr-only", "Country")
    assert has_element?(admin1, "#admin1-2", "California")

    admin1
    |> element("#admin1-filters")
    |> render_change(%{"filters" => %{"search" => "", "countryIso" => "MY"}})

    assert has_element?(admin1, "#admin1-1", "Kuala Lumpur")
    refute has_element?(admin1, "#admin1-2", "California")

    {:ok, postcodes, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

    assert has_element?(postcodes, "#postcodes-country-summary")
    assert has_element?(postcodes, "caption.sr-only", "Geonames postcodes")
    assert has_element?(postcodes, "th.text-right #postcodes-summary-sort-count")
    assert has_element?(postcodes, "#postcode-country-US", "United States")
    assert has_element?(postcodes, "#postcodes-sort-postcode")

    postcodes
    |> element("#postcodes-filters")
    |> render_change(%{"filters" => %{"search" => "San Francisco"}})

    assert has_element?(postcodes, "#postcode-2", "San Francisco")
    refute has_element?(postcodes, "#postcode-1", "Kuala Lumpur")
  end

  test "resets filter pagination and renders normal empty index states", %{conn: conn} do
    grant_capabilities!(["admin.geonames.list"])

    {:ok, countries, _html} =
      conn
      |> log_in_as()
      |> live(~p"/geonames/countries?#{%{page: 9}}")

    countries
    |> element("#countries-filters")
    |> render_change(%{"filters" => %{"search" => "missing"}})

    assert_patch(
      countries,
      ~p"/geonames/countries?#{%{search: "missing", page: 1, perPage: 25, sortBy: "country", sortDir: "asc"}}"
    )

    assert has_element?(countries, "#countries-table-empty", "No countries found.")

    {:ok, admin1, _html} = conn |> log_in_as() |> live(~p"/geonames/admin1")

    admin1
    |> element("#admin1-filters")
    |> render_change(%{
      "filters" => %{"search" => "missing", "countryIso" => ""}
    })

    assert has_element?(admin1, "#admin1-table-empty", "No Admin1 divisions found.")

    {:ok, postcodes, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

    postcodes
    |> element("#postcodes-filters")
    |> render_change(%{"filters" => %{"search" => "missing"}})

    assert has_element?(postcodes, "#postcodes-table-empty", "No postcodes found.")
  end

  test "uses compact pagination controls for country page size and sorting", %{conn: conn} do
    grant_capabilities!(["admin.geonames.list"])

    {:ok, countries, _html} = conn |> log_in_as() |> live(~p"/geonames/countries")

    assert has_element?(countries, "th[aria-sort='ascending'] #countries-sort-country")
    assert has_element?(countries, "th[aria-sort='none'] #countries-sort-population")

    countries
    |> element("#countries-pagination-page-size-form")
    |> render_change(%{"filters" => %{"perPage" => "50"}})

    assert_patch(
      countries,
      ~p"/geonames/countries?#{%{search: "", page: 1, perPage: 50, sortBy: "country", sortDir: "asc"}}"
    )

    countries
    |> element("#countries-sort-population")
    |> render_click()

    assert_patch(
      countries,
      ~p"/geonames/countries?#{%{search: "", page: 1, perPage: 50, sortBy: "population", sortDir: "desc"}}"
    )

    assert has_element?(countries, "th[aria-sort='descending'] #countries-sort-population")
    assert has_element?(countries, "th[aria-sort='none'] #countries-sort-country")
  end

  test "sorts admin1 divisions and postcodes tables with aria-sort", %{conn: conn} do
    grant_capabilities!(["admin.geonames.list"])

    {:ok, admin1, _html} = conn |> log_in_as() |> live(~p"/geonames/admin1")

    assert has_element?(admin1, "th[aria-sort='ascending'] #admin1-sort-country")
    assert has_element?(admin1, "th[aria-sort='none'] #admin1-sort-name")

    admin1
    |> element("#admin1-sort-name")
    |> render_click()

    assert_patch(
      admin1,
      ~p"/geonames/admin1?#{%{search: "", filterCountryIso: "", page: 1, perPage: 25, sortBy: "name", sortDir: "asc"}}"
    )

    assert has_element?(admin1, "th[aria-sort='ascending'] #admin1-sort-name")
    assert has_element?(admin1, "th[aria-sort='none'] #admin1-sort-country")

    {:ok, postcodes, _html} = conn |> log_in_as() |> live(~p"/geonames/postcodes")

    assert has_element?(postcodes, "th[aria-sort='ascending'] #postcodes-summary-sort-country")
    assert has_element?(postcodes, "th[aria-sort='ascending'] #postcodes-sort-country")

    postcodes
    |> element("#postcodes-summary-sort-iso")
    |> render_click()

    assert_patch(
      postcodes,
      ~p"/geonames/postcodes?#{%{search: "", page: 1, perPage: 25, sortBy: "country_name", sortDir: "asc", summarySortBy: "country_iso", summarySortDir: "asc"}}"
    )

    assert has_element?(postcodes, "th[aria-sort='ascending'] #postcodes-summary-sort-iso")
  end

  test "ignores a country update while one is already in progress" do
    socket = %Phoenix.LiveView.Socket{assigns: %{updating_countries?: true}}

    assert {:noreply, ^socket} = CountriesLive.handle_event("update-countries", %{}, socket)
  end

  test "handles country update async result with connection timeout error" do
    socket = %Phoenix.LiveView.Socket{
      endpoint: BilimbiWeb.Endpoint,
      router: BilimbiWeb.Router,
      assigns: %{
        __changed__: %{},
        flash: %{},
        updating_countries?: true
      }
    }

    assert {:noreply, socket} =
             CountriesLive.handle_async(
               :update_countries,
               {:ok,
                {:error,
                 {:download, :countries,
                  {:request, %Mint.TransportError{reason: :connect_timeout}}}}},
               socket
             )

    refute socket.assigns.updating_countries?
    assert socket.assigns.flash["error"] =~ "could not connect to download.geonames.org"
  end

  describe "country update outcome messages" do
    # `handle_async/3` reloads the page after flashing, so the socket needs the
    # index state that a mounted view would carry. Streams are configured too,
    # otherwise the reload raises before the flash can be read.
    defp update_socket do
      %Phoenix.LiveView.Socket{
        endpoint: BilimbiWeb.Endpoint,
        router: BilimbiWeb.Router,
        assigns: %{
          __changed__: %{},
          flash: %{},
          updating_countries?: true,
          index_state: %{
            search: "",
            page: 1,
            per_page: 25,
            sort_by: :iso,
            sort_dir: :asc
          },
          streams: %{
            __changed__: MapSet.new(),
            __configured__: %{},
            __ref__: 0,
            countries: %Phoenix.LiveView.LiveStream{
              name: :countries,
              dom_id: & &1.id,
              ref: "0",
              inserts: [],
              deletes: [],
              reset?: false,
              consumable?: false
            }
          }
        }
      }
    end

    defp flash_for(countries) do
      assert {:noreply, socket} =
               CountriesLive.handle_async(
                 :update_countries,
                 {:ok, {:ok, %{countries: countries}}},
                 update_socket()
               )

      socket.assigns.flash["info"]
    end

    test "a fallback says the update did not happen and dates the data" do
      cached_at = DateTime.new!(~D[2026-03-04], ~T[09:00:00], "Etc/UTC")

      message =
        flash_for(%{
          cached: true,
          download_status: :fallback,
          cached_at: cached_at,
          imported: 252,
          skipped: 50
        })

      # The whole point: an operator whose network died must not be told their
      # country data is current (#273).
      assert message =~ "were not updated"
      assert message =~ "04 Mar 2026"
      refute message =~ "Countries updated"
    end

    test "a 304 still reads as an update, because it is one" do
      message =
        flash_for(%{cached: true, download_status: 304, imported: 252, skipped: 50})

      assert message =~ "Countries updated from the current local GeoNames download"
    end

    test "a fresh download reads as an update" do
      message =
        flash_for(%{cached: false, download_status: 200, imported: 252, skipped: 50})

      assert message =~ "Countries updated from a fresh GeoNames download"
    end

    test "a fallback with no readable timestamp still refuses to claim an update" do
      message =
        flash_for(%{
          cached: true,
          download_status: :fallback,
          cached_at: nil,
          imported: 1,
          skipped: 0
        })

      assert message =~ "were not updated"
      refute message =~ "Countries updated"
    end
  end
end
