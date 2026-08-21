defmodule BilimbiWeb.CompanyLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.{Department, DepartmentType, LegalEntityType, Relationship}
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    GeonamesFixtures.insert_country!(%{iso: "MY", country: "Malaysia"})
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()
    AddressFixtures.create_geonames_tables!()
    AddressFixtures.create_address_tables!()
    AddressFixtures.insert_country!(%{iso: "MY", country: "Malaysia"})

    AddressFixtures.insert_country!(%{
      iso: "SG",
      iso3: "SGP",
      iso_numeric: "702",
      country: "Singapore",
      geoname_id: 1_880_251
    })

    AddressFixtures.insert_admin1!(%{
      code: "MY.14",
      name: "Kuala Lumpur",
      country_iso: "MY",
      admin1_code: "14"
    })

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Subsidiary",
      code: "bilimbi_subsidiary",
      parent_id: 73
    })

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  describe "Index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies")
    end

    test "redirects away when the actor lacks admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies")
    end

    test "lists only the current tenant's companies", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies td", "Bilimbi Industries")
      refute has_element?(view, "#companies td", "Elsewhere")
      refute has_element?(view, "#companies-add")
      assert has_element?(view, "#nav-admin-company[aria-current='page']")

      assert has_element?(
               view,
               "#nav-admin-company-department-type[href='/companies/department-types']"
             )

      assert has_element?(
               view,
               "#nav-admin-company-legal-entity-type[href='/companies/legal-entity-types']"
             )

      assert has_element?(view, "#nav-branch-admin[data-nav-default-expanded='true']")
      assert has_element?(view, "#nav-toggle-admin[aria-expanded='true']")
      assert has_element?(view, "#nav-children-admin:not([hidden])")
    end
  end

  describe "Show" do
    test "redirects away when the actor lacks admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73")
    end

    test "always shows the external accesses card, with its empty state", %{conn: conn} do
      # Belimbing renders this card unconditionally (`show.blade.php:259`), and
      # only guards the Subsidiaries card above it (`:41`). A card that vanishes
      # when empty reads as "not available here" rather than "none yet".
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "#company-external-accesses-card", "External Accesses")
      assert has_element?(view, "#company-external-accesses-table-empty", "No external accesses.")
      # `#company-external-accesses-table` is the tbody id, so the header row is
      # a sibling of it, not a descendant -- assert against the card.
      assert has_element?(view, "#company-external-accesses-card th", "User")
      refute has_element?(view, "#company-external-accesses-card th", "User ID")
      assert has_element?(view, "#company-external-accesses-card th", "Permissions")
      assert has_element?(view, "#company-external-accesses-card th", "Expires At")

      # The Subsidiaries card stays conditional, matching the source: this
      # fixture gives company 73 a child, so it renders here.
      assert has_element?(view, "#company-subsidiaries-card", "Subsidiaries")
    end

    test "renders external accesses with user name linked to user profile, or fallback for deleted/unknown user",
         %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])
      {:ok, scope} = Tenancy.scope(41)

      CompanyFixtures.insert_relationship_type!(11)
      CompanyFixtures.insert_relationship!(21, 73, 74)
      CompanyFixtures.insert_relationship!(22, 73, 74)

      {:ok, access1} =
        Company.create_external_access(scope, 73, %{
          relationship_id: 21,
          user_id: 91,
          permissions: ["view_orders"]
        })

      {:ok, access2} =
        Company.create_external_access(scope, 73, %{
          relationship_id: 22,
          user_id: 9999,
          permissions: ["manage_invoices"]
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Linked user name for Ada Lovelace (user 91)
      assert has_element?(
               view,
               "#company-external-accesses-table tr#access-#{access1.id} a[href='/users/91']",
               "Ada Lovelace"
             )

      # Fallback dash for unknown/deleted user 9999
      assert has_element?(
               view,
               "#company-external-accesses-table tr#access-#{access2.id} td",
               "—"
             )
    end

    test "hides write controls and rejects direct write events without update capability",
         %{conn: conn} do
      # This route is gated on `admin.company.view` -- a read capability -- and
      # `:if={@can_update?}` only hides the controls. The Departments,
      # Relationships and Department Types screens each have this test; the
      # Show screen did not, and every write handler was reachable by forging
      # the event.
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      refute has_element?(view, "#company-edit-details")

      render_submit(view, "save_details", %{
        "company" => %{"name" => "Forged Name", "status" => "archived"}
      })

      render_click(view, "add_activity", %{"activity" => "forged"})
      render_click(view, "remove_activity", %{"index" => "0"})
      render_submit(view, "save_metadata", %{"metadata" => ~s({"forged":true})})
      render_click(view, "save_timezone", %{"timezone" => "Etc/UTC"})
      render_click(view, "unlink_address", %{"id" => "1"})
      render_click(view, "toggle_address_primary", %{"id" => "1"})

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      stored = Repo.get!(Bilimbi.Core.Company.Schema, 73)
      assert stored.name == "Bilimbi Industries"
      assert stored.status == "active"
      assert stored.scope_activities in [nil, []]
      assert stored.metadata in [nil, %{}]
    end

    test "a forged non-numeric id is refused rather than crashing the view", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # `String.to_integer/1` raised on each of these, taking the LiveView down.
      render_click(view, "toggle_address_primary", %{"id" => "not-a-number"})
      render_click(view, "unlink_address", %{"id" => "../../etc"})
      render_click(view, "remove_activity", %{"index" => "abc"})

      render_submit(view, "save_address_priority", %{
        "id" => "oops",
        "priority" => "also-oops"
      })

      assert render(view) =~ "Bilimbi Industries"
    end

    test "renders the company with its users and back button", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "h1", "Bilimbi Industries")
      assert has_element?(view, "#company-back[href='/companies']", "Back to companies")
      assert has_element?(view, "#company-users-table td", "Ada Lovelace")

      assert has_element?(
               view,
               "#company-employees-table-empty",
               "No employees found for this company."
             )
    end

    test "applies URL-state search, sort, and page size to addresses and users", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])
      {:ok, scope} = Tenancy.scope(41)

      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace User",
        email: "grace@example.com"
      })

      {:ok, _headquarters} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{
            "label" => "Main HQ",
            "line1" => "456 Corporate Ave",
            "locality" => "Kuala Lumpur",
            "country_iso" => "MY"
          },
          %{kind: ["headquarters"], priority: 1}
        )

      {:ok, _branch} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{
            "label" => "Branch Office",
            "line1" => "789 Tech Hub",
            "locality" => "Kuala Lumpur",
            "country_iso" => "MY"
          },
          %{kind: ["branch"], priority: 2}
        )

      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> live(
          ~p"/companies/73?addresses_search=branch&addresses_sort=label&addresses_dir=desc&addresses_per_page=50&users_search=grace&users_sort=email&users_dir=desc&users_per_page=50"
        )

      assert has_element?(view, "#company-addresses-table td", "Branch Office")
      refute has_element?(view, "#company-addresses-table td", "Main HQ")

      assert has_element?(
               view,
               "#company-addresses-card th[aria-sort='descending'] button#company-addresses-sort-label"
             )

      assert has_element?(view, "#company-users-table td", "Grace User")
      refute has_element?(view, "#company-users-table td", "Ada Lovelace")

      assert has_element?(
               view,
               "#company-users th[aria-sort='descending'] button#company-users-sort-email"
             )
    end

    test "renders complete company show page with all cards and sections", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, scope} = Tenancy.scope(41)

      {:ok, type} =
        Company.create_legal_entity_type(%{
          code: "SDN_BHD",
          name: "Sdn Bhd",
          is_active: true
        })

      {:ok, _updated} =
        Company.update_company(scope, 73, %{
          legal_name: "Bilimbi Industries Sdn Bhd",
          legal_entity_type_id: type.id,
          registration_number: "REG-12345",
          tax_id: "TAX-98765",
          jurisdiction: "MY",
          email: "hq@bilimbi.test",
          website: "https://bilimbi.test",
          scope_activities: ["Software Development", "Cloud Infrastructure"],
          metadata: %{"employees_count" => 50}
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Details card
      assert has_element?(view, "#detail-name", "Bilimbi Industries")
      assert has_element?(view, "#detail-legal-name", "Bilimbi Industries Sdn Bhd")
      assert has_element?(view, "#detail-legal-entity-type", "Sdn Bhd")
      assert has_element?(view, "#detail-registration-number", "REG-12345")
      assert has_element?(view, "#detail-tax-id", "TAX-98765")
      assert has_element?(view, "#detail-jurisdiction", "Malaysia (MY)")
      assert has_element?(view, "#detail-email", "hq@bilimbi.test")
      assert has_element?(view, "#detail-website a", "https://bilimbi.test")

      # Activities
      assert has_element?(view, "#company-details-card", "Software Development")
      assert has_element?(view, "#company-details-card", "Cloud Infrastructure")

      # Metadata
      assert has_element?(view, "#company-metadata-display", "employees_count")

      # Subsidiaries
      assert has_element?(view, "#company-subsidiaries-card")
      assert has_element?(view, "#company-subsidiaries-table td", "Bilimbi Subsidiary")

      # Other cards
      assert has_element?(view, "#company-addresses-card")
      assert has_element?(view, "#company-timezone-card")
      assert has_element?(view, "#company-departments-card")
      assert has_element?(view, "#company-relationships-card")
    end

    test "edits company details via modal and validates fields", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Open modal
      view |> element("#edit-company-details-btn") |> render_click()
      assert has_element?(view, "#company-details-modal")

      # Validate blank name error
      view
      |> form("#company-details-form", %{"company" => %{"name" => ""}})
      |> render_change()

      assert has_element?(view, "#company-name-input + p", "can't be blank")

      # Save valid update
      view
      |> form("#company-details-form", %{
        "company" => %{
          "name" => "Bilimbi Global",
          "legal_name" => "Bilimbi Global Inc",
          "registration_number" => "REG-9999",
          "email" => "contact@bilimbi.global"
        }
      })
      |> render_submit()

      refute has_element?(view, "#company-details-modal")
      assert has_element?(view, "h1", "Bilimbi Global")
      assert has_element?(view, "#detail-name", "Bilimbi Global")
      assert has_element?(view, "#detail-legal-name", "Bilimbi Global Inc")
      assert has_element?(view, "#detail-registration-number", "REG-9999")
    end

    test "adds and removes business activities", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Add activity
      view
      |> form("#add-activity-form", %{"activity" => "consulting"})
      |> render_submit()

      assert has_element?(view, "#company-details-card", "consulting")

      # Add another activity
      view
      |> form("#add-activity-form", %{"activity" => "training"})
      |> render_submit()

      assert has_element?(view, "#company-details-card", "training")

      # Remove first activity
      view
      |> element("button[phx-click='remove_activity'][phx-value-index='0']")
      |> render_click()

      refute has_element?(view, "#company-details-card", "consulting")
      assert has_element?(view, "#company-details-card", "training")
    end

    test "edits, validates, and clears metadata JSON", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Open edit metadata
      view |> element("#edit-metadata-btn") |> render_click()
      assert has_element?(view, "#metadata-form")

      # Save invalid JSON
      view
      |> form("#metadata-form", %{"metadata" => "invalid-json-text"})
      |> render_submit()

      assert has_element?(view, "#flash-error", "Metadata was not saved. Enter valid JSON.")

      # Save valid JSON
      view
      |> form("#metadata-form", %{"metadata" => ~s({"founded": 2020, "tier": "enterprise"})})
      |> render_submit()

      refute has_element?(view, "#metadata-form")
      assert has_element?(view, "#company-metadata-display", "enterprise")

      # Clear metadata by submitting empty
      view |> element("#edit-metadata-btn") |> render_click()
      view |> form("#metadata-form", %{"metadata" => ""}) |> render_submit()
      refute has_element?(view, "#company-metadata-display")
    end

    test "updates and clears company default timezone", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Select timezone
      view
      |> form("#company-timezone-form", %{"timezone" => "Asia/Kuala_Lumpur"})
      |> render_change()

      assert has_element?(view, "#flash-info", "Timezone saved: Asia/Kuala_Lumpur")

      # Clear timezone
      view
      |> form("#company-timezone-form", %{"timezone" => ""})
      |> render_change()

      assert has_element?(view, "#flash-info", "Timezone cleared.")
    end

    test "attaches an existing address, toggles primary, changes priority, and unlinks it", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, scope} = Tenancy.scope(41)

      {:ok, address} =
        Bilimbi.Core.Address.create_address(scope, %{
          "label" => "Main HQ",
          "line1" => "456 Corporate Ave",
          "locality" => "Kuala Lumpur",
          "country_iso" => "MY"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Open attach modal
      view |> element("#attach-existing-address-btn") |> render_click()
      assert has_element?(view, "#company-attach-modal")

      # Submit attachment
      view
      |> form("#company-attach-address-form", %{
        "attach" => %{
          "address_id" => to_string(address.id),
          "kinds" => ["headquarters", "billing"],
          "is_primary" => "true",
          "priority" => "1"
        }
      })
      |> render_submit()

      refute has_element?(view, "#company-attach-modal")
      assert has_element?(view, "#attached-address-#{address.id} td", "Main HQ")
      assert has_element?(view, "#attached-address-#{address.id} span", "Headquarters")
      assert has_element?(view, "#attached-address-#{address.id} span", "Billing")
      assert has_element?(view, "#attached-address-#{address.id} span", "Yes")

      # Toggle primary
      view |> element("#toggle-primary-#{address.id}") |> render_click()
      assert has_element?(view, "#attached-address-#{address.id} span", "No")

      # Change priority
      render_click(view, "save_address_priority", %{
        "id" => to_string(address.id),
        "priority" => "5"
      })

      assert has_element?(view, "#attached-address-#{address.id} td", "5")

      # Unlink address
      view |> element("#unlink-address-#{address.id}") |> render_click()
      assert has_element?(view, "#company-addresses-table-empty", "No addresses linked.")
    end

    test "creates and attaches a new address with geonames integration", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Open create & attach modal
      view |> element("#create-attach-address-btn") |> render_click()
      assert has_element?(view, "#company-create-address-modal")

      # Submit create & attach form
      view
      |> form("#create-attach-address-form", %{
        "address" => %{
          "label" => "Branch Office",
          "line1" => "789 Tech Hub",
          "locality" => "Kuala Lumpur",
          "country_iso" => "MY",
          "kinds" => ["branch"],
          "priority" => "2"
        }
      })
      |> render_submit()

      refute has_element?(view, "#company-create-address-modal")
      assert has_element?(view, "#company-addresses-table td", "Branch Office")
      assert has_element?(view, "#company-addresses-table span", "Branch")
    end

    test "hides write controls when actor lacks admin.company.update", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      refute has_element?(view, "#edit-company-details-btn")
      refute has_element?(view, "#add-activity-form")
      refute has_element?(view, "#edit-metadata-btn")
      refute has_element?(view, "#create-attach-address-btn")
      refute has_element?(view, "#attach-existing-address-btn")
    end

    test "redirects away for another tenant's company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/75")
    end

    test "redirects away for a missing company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/9999")
    end
  end

  describe "Create" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/create")
    end

    test "redirects away when the actor lacks admin.company.create", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/create")
    end

    test "shows the add control on the index when the actor can create", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies-add[href='/companies/create']")
    end

    test "creates a company through the domain API and slugs a blank code", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      view
      |> form("#company-form", company: %{name: "North Branch", status: "active"})
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path == "/companies"
      assert flash["info"] == "Company created successfully."

      {:ok, index, _html} = conn |> log_in_as() |> live(path)
      assert has_element?(index, "#companies td", "North Branch")

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      created = Enum.find(companies, &(&1.name == "North Branch"))
      assert created.code == "north_branch"
    end

    test "company-scoped actor sees only their company as parent and cannot forge a sibling",
         %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-parent option[value='73']")
      refute has_element?(view, "#company-parent option[value='74']")
      refute has_element?(view, "#company-parent option[value='75']")

      html =
        render_submit(view, "save", %{
          "company" => %{
            "parent_id" => "74",
            "name" => "Forged Child",
            "status" => "active"
          }
        })

      assert html =~ "is not available"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Forged Child"))
    end

    test "forged non-positive parent ids fail closed without a write", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        render_submit(view, "save", %{
          "company" => %{
            "parent_id" => "-1",
            "name" => "Invalid Parent Child",
            "status" => "active"
          }
        })

      assert html =~ "is not available"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Invalid Parent Child"))
    end

    test "revoking create capability after mount prevents a parentless write", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")
      {:ok, scope} = Tenancy.scope(41)

      assert {:ok, :stored} =
               Bilimbi.Base.Authz.put_principal_capability(
                 scope,
                 73,
                 :user,
                 91,
                 "admin.company.create",
                 false
               )

      html =
        render_submit(view, "save", %{
          "company" => %{
            "parent_id" => "",
            "name" => "Revoked Create",
            "status" => "active"
          }
        })

      assert html =~ "is not available"
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Revoked Create"))
    end

    test "tenant-wide company authority exposes sibling parents but not another tenant",
         %{conn: conn} do
      grant_capabilities!([
        "admin.company.create",
        "admin.company.tenant-wide.manage"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-parent option[value='73']")
      assert has_element?(view, "#company-parent option[value='74']")
      refute has_element?(view, "#company-parent option[value='75']")

      view
      |> form("#company-form",
        company: %{parent_id: "74", name: "Authorized Child", status: "active"}
      )
      |> render_submit()

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      assert Enum.any?(companies, &(&1.name == "Authorized Child" and &1.parent_id == 74))

      {:ok, forged, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        render_submit(forged, "save", %{
          "company" => %{
            "parent_id" => "75",
            "name" => "Cross Tenant Child",
            "status" => "active"
          }
        })

      assert html =~ "is not available"
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Cross Tenant Child"))
    end

    test "rejects invalid JSON payloads without inserting", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        view
        |> form("#company-form",
          company: %{name: "Broken JSON Co", status: "active", metadata_json: "{not json"}
        )
        |> render_submit()

      assert html =~ "must be valid JSON"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Broken JSON Co"))
    end

    test "renders jurisdiction country select and persists valid country", %{conn: conn} do
      grant_capabilities!(["admin.company.create", "admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-jurisdiction")
      assert has_element?(view, "#company-jurisdiction option[value='MY']", "Malaysia (MY)")

      # Belimbing labels each select's empty option differently and on purpose:
      # "None" for Parent Company, "Select type..." for Legal Entity Type,
      # "Select country..." here (`create.blade.php:88`).
      assert has_element?(view, "#company-jurisdiction option[value='']", "Select country...")

      view
      |> form("#company-form",
        company: %{name: "MY Branch", status: "active", jurisdiction: "MY"}
      )
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path == "/companies"

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      created = Enum.find(companies, &(&1.name == "MY Branch"))
      assert Repo.get!(Bilimbi.Core.Company.Schema, created.id).jurisdiction == "MY"
    end

    test "rejects forged invalid country ISO without persisting", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        view
        |> element("#company-form")
        |> render_submit(%{
          "company" => %{"name" => "Fake Co", "status" => "active", "jurisdiction" => "XX"}
        })

      assert html =~ "must be a valid country ISO code"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Fake Co"))
    end
  end

  describe "Legal Entity Types Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/legal-entity-types")
    end

    # Belimbing gates both type index screens on `admin.company.list`, not
    # `.view` (`app/Core/Company/Routes/web.php:25-30`), and that matches how
    # this app already splits the two: `/companies` is `.list`, `/companies/:id`
    # is `.view`. These are index screens.
    test "redirects without admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/legal-entity-types")
    end

    test "creates, validates, edits, toggles, and deletes legal entity types", %{conn: conn} do
      grant_capabilities!([
        "admin.company.list",
        "admin.company.create",
        "admin.company.update",
        "admin.company.delete"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")

      assert has_element?(view, "h1", "Legal Entity Types")
      assert has_element?(view, "#nav-admin-company-legal-entity-type[aria-current='page']")
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")

      # Open new modal
      view |> element("#new-legal-entity-type-btn") |> render_click()
      assert has_element?(view, "#legal-entity-type-modal")

      # Validate
      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{"code" => "LLC", "name" => ""}
      })
      |> render_change()

      assert has_element?(view, "#legal-entity-type-name + p", "can't be blank")

      # Save
      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{
          "code" => "LLC",
          "name" => "Limited Liability Company",
          "description" => "Standard LLC"
        }
      })
      |> render_submit()

      refute has_element?(view, "#legal-entity-type-modal")
      assert has_element?(view, "#legal-entity-types td", "Limited Liability Company")
      assert has_element?(view, "#legal-entity-types code", "LLC")

      # Edit
      type = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.LegalEntityType, code: "LLC")
      view |> element("#edit-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-type-modal")

      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{
          "name" => "Limited Liability Corp"
        }
      })
      |> render_submit()

      assert has_element?(view, "#legal-entity-types td", "Limited Liability Corp")

      # Toggle active
      view |> element("#toggle-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types span", "inactive")

      view |> element("#toggle-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types span", "active")

      # Delete
      view |> element("#delete-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")
    end

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_legal_entity_type(%{
          code: "LLC",
          name: "Limited Liability Company",
          is_active: true
        })

      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")

      refute has_element?(view, "#new-legal-entity-type-btn")
      refute has_element?(view, "#toggle-type-#{type.id}")
      refute has_element?(view, "#edit-type-#{type.id}")
      refute has_element?(view, "#delete-type-#{type.id}")

      render_click(view, "toggle_active", %{"id" => to_string(type.id)})
      render_click(view, "delete", %{"id" => to_string(type.id)})

      render_submit(view, "save", %{
        "legal_entity_type" => %{"code" => "NEW", "name" => "Unauthorized"}
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(LegalEntityType, type.id).is_active
      refute Repo.get_by(LegalEntityType, code: "NEW")
    end
  end

  describe "Department Types Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/department-types")
    end

    test "redirects without admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/department-types")
    end

    test "creates, filters, edits, toggles, and deletes department types", %{conn: conn} do
      grant_capabilities!([
        "admin.company.list",
        "admin.company.create",
        "admin.company.update",
        "admin.company.delete"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")

      assert has_element?(view, "h1", "Department Types")
      assert has_element?(view, "#nav-admin-company-department-type[aria-current='page']")

      # Create Operational Type
      view |> element("#new-department-type-btn") |> render_click()
      assert has_element?(view, "#department-type-modal")

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "code" => "ENG",
          "name" => "Engineering",
          "category" => "operational",
          "description" => "Software and hardware engineering"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Engineering")

      # Create Administrative Type
      view |> element("#new-department-type-btn") |> render_click()

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "code" => "HR",
          "name" => "Human Resources",
          "category" => "administrative"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Human Resources")

      # Filter by category
      view |> element("button", "Administrative") |> render_click()
      assert has_element?(view, "#department-types td", "Human Resources")
      refute has_element?(view, "#department-types td", "Engineering")

      view |> element("button", "All") |> render_click()
      assert has_element?(view, "#department-types td", "Engineering")
      assert has_element?(view, "#department-types td", "Human Resources")

      # Edit
      eng = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.DepartmentType, code: "ENG")
      view |> element("#edit-dept-type-#{eng.id}") |> render_click()

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "name" => "Software Engineering"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Software Engineering")

      # Delete HR
      hr = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.DepartmentType, code: "HR")
      view |> element("#delete-dept-type-#{hr.id}") |> render_click()
      refute has_element?(view, "#department-types td", "Human Resources")
    end

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational",
          is_active: true
        })

      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")

      refute has_element?(view, "#new-department-type-btn")
      refute has_element?(view, "#toggle-dept-type-#{type.id}")
      refute has_element?(view, "#edit-dept-type-#{type.id}")
      refute has_element?(view, "#delete-dept-type-#{type.id}")

      render_click(view, "toggle_active", %{"id" => to_string(type.id)})
      render_click(view, "delete", %{"id" => to_string(type.id)})

      render_submit(view, "save", %{
        "department_type" => %{
          "code" => "NEW",
          "name" => "Unauthorized",
          "category" => "operational"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(DepartmentType, type.id).is_active
      refute Repo.get_by(DepartmentType, code: "NEW")
    end
  end

  describe "Company Departments Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/73/departments")
    end

    test "redirects without admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73/departments")
    end

    test "manages company departments and status transitions", %{conn: conn} do
      grant_capabilities!(["admin.company.view", "admin.company.update"])

      {:ok, eng} =
        Bilimbi.Core.Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      assert has_element?(view, "h1", "Bilimbi Industries — Departments")
      assert has_element?(view, "#company-departments-empty")

      # Add Department
      view |> element("#add-dept-btn") |> render_click()
      assert has_element?(view, "#department-modal")

      view
      |> form("#department-form", %{
        "department" => %{
          "department_type_id" => to_string(eng.id),
          "status" => "active"
        }
      })
      |> render_submit()

      refute has_element?(view, "#department-modal")
      assert has_element?(view, "#company-departments td", "Engineering")

      # Get department record
      dept = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.Department, company_id: 73)

      # Suspend
      view |> element("#suspend-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "suspended")

      # Activate
      view |> element("#activate-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "active")

      # Deactivate
      view |> element("#deactivate-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "inactive")

      # Remove
      view |> element("#delete-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments-empty")
    end

    test "hides write controls and rejects direct write events without update capability", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, department} =
        Company.create_department(scope, 73, %{
          "department_type_id" => to_string(type.id),
          "status" => "active"
        })

      grant_capabilities!(["admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      refute has_element?(view, "#add-dept-btn")
      refute has_element?(view, "#suspend-dept-#{department.id}")
      refute has_element?(view, "#deactivate-dept-#{department.id}")
      refute has_element?(view, "#delete-dept-#{department.id}")

      render_click(view, "update_status", %{
        "id" => to_string(department.id),
        "status" => "suspended"
      })

      render_click(view, "delete", %{"id" => to_string(department.id)})

      render_submit(view, "save", %{
        "department" => %{
          "department_type_id" => to_string(type.id),
          "status" => "inactive"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(Department, department.id).status == "active"
      assert Repo.aggregate(Department, :count) == 1
    end
  end

  describe "Company Relationships Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/73/relationships")
    end

    test "redirects without admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73/relationships")
    end

    test "manages relationships and date edits", %{conn: conn} do
      CompanyFixtures.insert_relationship_type!(11)
      grant_capabilities!(["admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")

      assert has_element?(view, "h1", "Bilimbi Industries — Relationships")
      assert has_element?(view, "#company-relationships-empty")

      # Add Relationship
      view |> element("#add-rel-btn") |> render_click()
      assert has_element?(view, "#relationship-modal")

      view
      |> form("#relationship-form", %{
        "relationship" => %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01",
          "effective_to" => "2026-12-31"
        }
      })
      |> render_submit()

      refute has_element?(view, "#relationship-modal")
      assert has_element?(view, "#company-relationships td", "Bilimbi Subsidiary")
      assert has_element?(view, "#company-relationships td", "Customer")
      assert has_element?(view, "#company-relationships span", "Outgoing")

      # Edit dates
      rel = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.Relationship, company_id: 73)
      view |> element("#edit-rel-#{rel.id}") |> render_click()
      assert has_element?(view, "#relationship-modal")

      view
      |> form("#relationship-form", %{
        "relationship" => %{
          "effective_to" => "2027-12-31"
        }
      })
      |> render_submit()

      assert has_element?(view, "#company-relationships", "2027-12-31")

      # Delete
      view |> element("#delete-rel-#{rel.id}") |> render_click()
      assert has_element?(view, "#company-relationships-empty")
    end

    test "hides write controls and rejects direct write events without update capability", %{
      conn: conn
    } do
      CompanyFixtures.insert_relationship_type!(11)
      {:ok, scope} = Tenancy.scope(41)

      {:ok, relationship} =
        Company.create_relationship(scope, 73, %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01"
        })

      grant_capabilities!(["admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")

      refute has_element?(view, "#add-rel-btn")
      refute has_element?(view, "#edit-rel-#{relationship.id}")
      refute has_element?(view, "#delete-rel-#{relationship.id}")

      render_click(view, "delete", %{"id" => to_string(relationship.id)})

      render_submit(view, "save", %{
        "relationship" => %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-02-01"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert is_nil(Repo.get!(Relationship, relationship.id).deleted_at)
      assert Repo.aggregate(Relationship, :count) == 1
    end
  end
end
