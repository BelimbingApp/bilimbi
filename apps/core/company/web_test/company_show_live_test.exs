defmodule BilimbiWeb.CompanyShowLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()
    GeonamesFixtures.insert_country!(%{iso: "MY", country: "Malaysia"})

    GeonamesFixtures.insert_admin1!(%{
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

    UserFixtures.insert_user!(%{
      id: 96,
      company_id: 75,
      name: "Grace Hopper",
      email: "grace.hopper@example.com"
    })

    :ok
  end

  describe "Show" do
    test "header shows the name once, with legal name or code as subtitle", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])
      conn = log_in_as(conn)

      # No distinct legal name: subtitle falls back to the code (#622).
      {:ok, view, _html} = live(conn, ~p"/companies/73")
      assert has_element?(view, "h1", "Bilimbi Industries")
      assert has_element?(view, "header p", "bilimbi_industries")

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _} =
        Company.update_company(scope, 73, %{legal_name: "Bilimbi Industries Sdn. Bhd."})

      {:ok, view, _html} = live(conn, ~p"/companies/73")
      assert has_element?(view, "header p", "Bilimbi Industries Sdn. Bhd.")
    end

    test "relationships embed shows the effective period", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])
      CompanyFixtures.insert_relationship_type!(11)
      CompanyFixtures.insert_relationship!(21, 73, 74)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "#company-relationships-card th", "Effective")
      assert has_element?(view, "#company-relationships-table td", "Always → Present")
    end

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

      refute has_element?(view, "#company-details-card [phx-hook='InlineEdit']")
      refute has_element?(view, "#company-status button")

      render_hook(view, "save_field", %{"id" => "73", "name" => "Forged Name"})
      render_hook(view, "edit_field", %{"field" => "legal_entity_type_id"})
      render_click(view, "request_lifecycle", %{"operation" => "archive"})
      render_submit(view, "apply_lifecycle", %{"reason" => "forged"})
      render_hook(view, "add_activity", %{"id" => "73", "activity" => "forged"})
      render_click(view, "remove_activity", %{"index" => "0"})
      render_click(view, "edit_metadata", %{})
      render_submit(view, "save_metadata", %{"metadata" => ~s({"forged":true})})
      render_change(view, "save_timezone", %{"timezone" => "Etc/UTC"})

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      refute has_element?(view, "#company-lifecycle-modal")
      refute has_element?(view, "#company-metadata-editor-input")

      stored = Repo.get!(Bilimbi.Core.Company.Schema, 73)
      assert stored.name == "Bilimbi Industries"
      assert stored.status == "active"
      assert stored.scope_activities in [nil, []]
      assert stored.metadata in [nil, %{}]
    end

    test "a forged non-numeric id is refused rather than crashing the view", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # `String.to_integer/1` raised on a non-numeric index, taking the LiveView
      # down. (The address writes moved to the core/address panel, which guards
      # its own ids; see the panel's forged-write test above.)
      render_click(view, "remove_activity", %{"index" => "abc"})

      assert has_element?(view, "h1", "Bilimbi Industries")
    end

    test "renders the company with its users and back link", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "h1", "Bilimbi Industries")

      assert has_element?(
               view,
               "#company-back[href='/companies'][title='Back to companies']",
               "Back"
             )

      assert has_element?(view, "#company-users-table td", "Ada Lovelace")

      assert has_element?(
               view,
               "#company-employees-table-empty",
               "No employees found for this company."
             )
    end

    test "reaches Departments and Relationships through demoted links on their sections, not header buttons",
         %{conn: conn} do
      # Belimbing's admin/companies/show puts one quiet "Manage" affordance,
      # carrying the cog, on each of these sections and nothing in the header.
      # A viewer holding only admin.company.view may open both pages, which
      # are gated on that same capability, so the links show for them too.
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(
               view,
               "#company-departments-card a#company-departments-manage[href='/companies/73/departments'][title='Manage departments']",
               "Manage"
             )

      assert has_element?(view, "#company-departments-manage .hero-cog-6-tooth")

      assert has_element?(
               view,
               "#company-relationships-card a#company-relationships-manage[href='/companies/73/relationships'][title='Manage relationships']",
               "Manage"
             )

      assert has_element?(view, "#company-relationships-manage .hero-cog-6-tooth")

      for id <- ~w(company-departments-manage company-relationships-manage) do
        assert has_element?(view, "a##{id}.text-link")
        refute has_element?(view, "a##{id}.border")
        refute has_element?(view, "a##{id}.bg-action")
        refute has_element?(view, "a##{id}.shadow-sm")
      end

      # The page header (inside <main>; the shell's top bar is its own
      # <header>) holds no Departments or Relationships link, and without
      # audit permission no History disclosure: only the pin and the back link.
      refute has_element?(view, "main header a[href='/companies/73/departments']")
      refute has_element?(view, "main header a[href='/companies/73/relationships']")
      refute has_element?(view, "main header", "Departments")
      refute has_element?(view, "main header", "Relationships")
      refute has_element?(view, "main header button:not(#company-pin)")
      assert has_element?(view, "main header #company-back", "Back")
    end

    test "shows record history only with audit permission and filters to this company", %{
      conn: conn
    } do
      {:ok, scope} = Tenancy.scope(41)

      {:ok, _visible} =
        Audit.record_mutation(scope, %{
          company_id: 73,
          actor_type: "user",
          actor_id: 91,
          auditable_type: Company.addressable_identity(),
          auditable_id: "73",
          subject_name: "Bilimbi Industries",
          event: "updated",
          occurred_at: ~N[2026-08-18 10:00:00],
          old_values: %{"name" => "Old Name"},
          new_values: %{"name" => "Bilimbi Industries"}
        })

      {:ok, _other} =
        Audit.record_mutation(scope, %{
          company_id: 74,
          actor_type: "user",
          actor_id: 91,
          auditable_type: Company.addressable_identity(),
          auditable_id: "74",
          subject_name: "Bilimbi Subsidiary",
          event: "updated",
          occurred_at: ~N[2026-08-18 10:01:00],
          old_values: %{"name" => "Other Old"},
          new_values: %{"name" => "Other New"}
        })

      grant_capabilities!(["admin.company.list", "admin.company.view"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")
      refute has_element?(view, "#company-record-history-toggle")
      refute has_element?(view, "#company-record-history .hero-clock")

      grant_capabilities!("admin.audit.log.list")
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # History is a demoted labelled disclosure: Belimbing's clock and its
      # word, in the same quiet treatment as the back link, with the open
      # state on the button.
      assert has_element?(
               view,
               "button#company-record-history-toggle[title='History'][aria-expanded='false'][aria-controls='company-record-history-panel']",
               "History"
             )

      assert has_element?(view, "#company-record-history-toggle .hero-clock")
      assert has_element?(view, "button#company-record-history-toggle.text-link")
      refute has_element?(view, "#company-record-history-toggle .sr-only")
      refute has_element?(view, "summary#company-record-history-toggle")
      refute has_element?(view, "#company-record-history-toggle.bg-action")
      refute has_element?(view, "#company-record-history-panel")

      view |> element("#company-record-history-toggle") |> render_click()
      assert has_element?(view, "#company-record-history-panel", "Old Name")
      assert has_element?(view, "#company-record-history-panel", "Bilimbi Industries")
      refute has_element?(view, "#company-record-history-panel", "Other Old")
    end

    test "applies URL-state search, sort, and page size to users", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      UserFixtures.insert_user!(%{
        id: 92,
        company_id: 73,
        name: "Grace User",
        email: "grace@example.com"
      })

      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> live(
          ~p"/companies/73?users_search=grace&users_sort=email&users_dir=desc&users_per_page=50"
        )

      assert has_element?(view, "#company-users-table td", "Grace User")
      refute has_element?(view, "#company-users-table td", "Ada Lovelace")

      assert has_element?(
               view,
               "#company-users-panel th[aria-sort='descending'] button#company-users-sort-email"
             )
    end

    test "renders complete company show page with all cards and sections", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, scope} = Tenancy.scope(41)

      {:ok, type} =
        Company.create_legal_entity_type(scope!(), %{
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

      assert has_element?(
               view,
               "#company-pin[data-nav-pin-record='true'][data-nav-pin-label='Administration / Companies / Bilimbi Industries'][data-nav-pin-url='/companies/73']"
             )

      # Details card
      assert has_element?(view, "#detail-name", "Bilimbi Industries")
      assert has_element?(view, "#detail-legal-name", "Bilimbi Industries Sdn Bhd")
      assert has_element?(view, "#detail-legal-entity-type", "Sdn Bhd")
      assert has_element?(view, "#detail-registration-number", "REG-12345")
      assert has_element?(view, "#detail-tax-id", "TAX-98765")
      assert has_element?(view, "#detail-jurisdiction", "Malaysia (MY)")
      assert has_element?(view, "#detail-email", "hq@bilimbi.test")
      assert has_element?(view, "#detail-website", "https://bilimbi.test")

      # Activities
      assert has_element?(view, "#company-details-card", "Software Development")
      assert has_element?(view, "#company-details-card", "Cloud Infrastructure")

      # Metadata
      assert has_element?(view, "#company-metadata-editor-display", "employees_count")

      # Subsidiaries
      assert has_element?(view, "#company-subsidiaries-card")
      assert has_element?(view, "#company-subsidiaries-table td", "Bilimbi Subsidiary")

      # Other cards
      assert has_element?(view, "#company-addresses-panel")
      assert has_element?(view, "#company-timezone-card")
      assert has_element?(view, "#company-departments-card")
      assert has_element?(view, "#company-relationships-card")
    end

    test "departments table names the head employee via the principal directory", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, scope} = Tenancy.scope(41)

      # The head is a plain employee in company 73. core/company names it across
      # the boundary through base/principal_directory (ADR 0014), never by
      # depending on core/employee.
      {:ok, _type} =
        Employee.create_employee_type(scope, 73, %{code: "field_staff", label: "Field Staff"})

      {:ok, head} =
        Employee.create_employee(scope, 73, %{
          employee_number: "E-100",
          full_name: "Grace Hopper",
          employee_type: "field_staff",
          status: "active"
        })

      {:ok, eng} = Company.create_department_type(scope!(), %{code: "ENG", name: "Engineering"})
      {:ok, ops} = Company.create_department_type(scope!(), %{code: "OPS", name: "Operations"})

      {:ok, _headed} =
        Company.create_department(scope, 73, %{
          department_type_id: eng.id,
          head_id: head.id,
          status: "active"
        })

      {:ok, _headless} =
        Company.create_department(scope, 73, %{department_type_id: ops.id, status: "active"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The "Head" column header lives in the card's <thead>, outside the table body.
      assert has_element?(view, "#company-departments-card th", "Head")

      # The headed department shows the resolved employee name...
      assert has_element?(view, "#company-departments-table td", "Grace Hopper")
      # ...and the headless one falls back to the em dash, never a bare id.
      assert has_element?(view, "#company-departments-table td", "—")
      refute has_element?(view, "#company-departments-table", "head_id")
    end

    test "presents the company facts as the shared list under one section heading", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The facts are rows of one definition list; every value cell keeps its id.
      assert has_element?(view, "#company-details-card dl dd#detail-name", "Bilimbi Industries")
      assert has_element?(view, "#company-details-card dl dd#detail-code", "bilimbi_industries")
      assert has_element?(view, "#company-details-card dl dd#detail-parent", "None")
      assert has_element?(view, "#company-details-card dl dd#scope-activities-section")
      assert has_element?(view, "#company-details-card dl dd#company-metadata")
      assert has_element?(view, "#company-details-card dl dt", "Business Activities")
      assert has_element?(view, "#company-details-card dl dt", "Metadata")

      # One heading treatment: every section is a named region whose title is
      # the shared level-two heading, and none writes its own h3.
      for id <-
            ~w(company-details company-timezone company-subsidiaries company-departments company-relationships company-external-accesses) do
        assert has_element?(
                 view,
                 "##{id}-card[role='region'][aria-labelledby='#{id}-heading'] h2##{id}-heading"
               )

        refute has_element?(view, "##{id}-card h3")
      end

      assert has_element?(view, "#company-departments-heading + span", "0")
    end

    test "a viewer without admin.company.update sees the facts with no editors", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, _updated} =
        Company.update_company(scope, 73, %{
          legal_name: "Bilimbi Industries Sdn Bhd",
          jurisdiction: "MY",
          website: "https://bilimbi.test",
          scope_activities: ["Software Development"],
          metadata: %{"employees_count" => 50}
        })

      {:ok, _} =
        Settings.put("localization.timezone", "Asia/Kuala_Lumpur", SettingsScope.company(73, 41))

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Every fact is on screen as its stored value...
      assert has_element?(view, "#detail-name", "Bilimbi Industries")
      assert has_element?(view, "#detail-code", "bilimbi_industries")
      assert has_element?(view, "#detail-legal-name", "Bilimbi Industries Sdn Bhd")
      assert has_element?(view, "#detail-status", "Active")
      assert has_element?(view, "#detail-legal-entity-type", "—")
      assert has_element?(view, "#detail-jurisdiction", "Malaysia (MY)")
      assert has_element?(view, "#detail-website a[href='https://bilimbi.test']")
      assert has_element?(view, "#detail-parent", "None")
      assert has_element?(view, "#scope-activities-section", "Software Development")
      assert has_element?(view, "#company-metadata-editor", "employees_count")
      assert has_element?(view, "#detail-timezone", "Asia/Kuala_Lumpur")

      # ...and nothing edits it: no in-place text control, no choice trigger,
      # no select, no form, no pencil and no chip removal in either fact
      # section -- the value, not a disabled control.
      for card <- ~w(company-details-card company-timezone-card) do
        refute has_element?(view, "##{card} [phx-hook='InlineEdit']")
        refute has_element?(view, "##{card} button")
        refute has_element?(view, "##{card} select")
        refute has_element?(view, "##{card} form")
        refute has_element?(view, "##{card} input")
        refute has_element?(view, "##{card} textarea")
      end

      refute has_element?(view, "#company-metadata-editor-display")
      refute has_element?(view, "#company-new-activity")
      refute has_element?(view, "#remove-activity-0")
    end

    test "the addresses panel is the shared table, sorted by the panel and edited in place", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, scope} = Tenancy.scope(41)

      {:ok, hq} =
        Address.create_address(scope, %{
          label: "Head Office",
          line1: "1 Market Street",
          locality: "Kuala Lumpur",
          country_iso: "MY"
        })

      {:ok, depot} = Address.create_address(scope, %{label: "Depot", line1: "9 Dock Road"})

      {:ok, :attached} =
        Address.attach_to_company(scope, hq.id, 73, %{
          kind: ["headquarters"],
          is_primary: true,
          priority: 0
        })

      {:ok, :attached} =
        Address.attach_to_company(scope, depot.id, 73, %{kind: ["shipping"], priority: 5})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The panel is a section like the page's own: shared heading with its
      # count, and the shared table under it with no hand-written table.
      assert has_element?(
               view,
               "#company-addresses-panel h2#company-addresses-heading",
               "Addresses"
             )

      assert has_element?(view, "#company-addresses-heading + span", "2")
      refute has_element?(view, "#company-addresses-panel h3")
      assert has_element?(view, "#company-addresses-panel caption", "Company addresses")

      assert has_element?(
               view,
               "#company-addresses-panel th[aria-sort='ascending'] button#addresses-table-sort-label"
             )

      assert has_element?(view, "tbody#addresses-table tr#address-row-#{hq.id}")

      # The label opens the address's own page, carrying the company for the way back.
      assert has_element?(
               view,
               "#address-link-#{hq.id}[href='/addresses/#{hq.id}?company=73']",
               "Head Office"
             )

      assert has_element?(view, "#address-row-#{hq.id}", "1 Market Street, Kuala Lumpur, MY")

      # Sorting is the panel's own event, so it must reach the component.
      view |> element("#addresses-table-sort-priority") |> render_click()
      assert has_element?(view, "th[aria-sort='ascending'] #addresses-table-sort-priority")
      refute has_element?(view, "th[aria-sort='ascending'] #addresses-table-sort-label")

      view |> element("#addresses-table-sort-priority") |> render_click()
      assert has_element?(view, "th[aria-sort='descending'] #addresses-table-sort-priority")

      rows = view |> element("#addresses-table") |> render()
      {depot_at, _} = :binary.match(rows, "address-row-#{depot.id}")
      {hq_at, _} = :binary.match(rows, "address-row-#{hq.id}")
      assert depot_at < hq_at

      # Kinds are a choice fact: the read state is the trigger.
      assert has_element?(
               view,
               "button#edit-kinds-#{depot.id}[aria-label='Edit kinds']",
               "Shipping"
             )

      # The primary flag toggles on click and says which state it is in.
      view |> element("#toggle-primary-#{depot.id}[aria-pressed='false']") |> render_click()
      assert has_element?(view, "#toggle-primary-#{depot.id}[aria-pressed='true']")

      # Priority commits in place through the shared editor, addressed to the
      # panel, and the outcome reports through the panel notice.
      assert has_element?(
               view,
               "#address-priority-#{depot.id}[phx-hook='InlineEdit'][data-save-event='save_address_priority'][data-id='#{depot.id}']"
             )

      refute has_element?(view, "#priority-form-#{depot.id}")

      view
      |> element("#address-priority-#{depot.id}")
      |> render_hook("save_address_priority", %{"id" => to_string(depot.id), "priority" => "2"})

      assert has_element?(
               view,
               "#company-addresses-panel-notice[role='status'][data-kind='success']",
               "Address setting updated."
             )

      assert has_element?(view, "#address-priority-#{depot.id} [data-role='text']", "2")

      {:ok, attached} = Address.list_company_attached_addresses(scope, 73)
      assert Enum.find(attached, &(&1.id == depot.id)).priority == 2

      # A value that is not a whole number is refused and said so, never stored as 0.
      view
      |> element("#address-priority-#{depot.id}")
      |> render_hook("save_address_priority", %{"id" => to_string(depot.id), "priority" => "high"})

      assert has_element?(
               view,
               "#company-addresses-panel-notice[role='alert'][data-kind='error']",
               "Priority was not saved"
             )

      {:ok, attached} = Address.list_company_attached_addresses(scope, 73)
      assert Enum.find(attached, &(&1.id == depot.id)).priority == 2

      # Unlinking is a demoted icon action carrying Belimbing's link-slash
      # glyph, confirmed through the shared dialog rather than a native one.
      assert has_element?(
               view,
               "button#unlink-address-#{depot.id}[aria-label='Unlink address'][title='Unlink']"
             )

      refute has_element?(view, "#unlink-address-#{depot.id}[data-confirm]")
      assert has_element?(view, "#unlink-address-#{depot.id} .hero-link-slash")

      view |> element("#unlink-address-#{depot.id}") |> render_click()

      assert_modal_dialog(
        view,
        "unlink-address-confirm",
        "“Depot” will be unlinked from this company."
      )

      assert has_element?(
               view,
               "#unlink-address-confirm-description",
               "The address itself is kept and can be attached again."
             )

      # Cancelling keeps the link.
      view |> element("#unlink-address-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#unlink-address-confirm")
      assert has_element?(view, "#address-row-#{depot.id}")
      assert has_element?(view, "#company-addresses-heading + span", "2")

      # Confirming unlinks it; the address itself survives.
      view |> element("#unlink-address-#{depot.id}") |> render_click()
      view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

      refute has_element?(view, "#unlink-address-confirm")
      refute has_element?(view, "#address-row-#{depot.id}")
      assert has_element?(view, "#company-addresses-heading + span", "1")

      assert has_element?(
               view,
               "#company-addresses-panel-notice[role='status'][data-kind='success']",
               "Address unlinked."
             )

      assert {:ok, _depot} = Address.get_address(scope, depot.id)
    end

    test "unlinking an address whose link is already gone informs rather than refuses", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)
      {:ok, depot} = Address.create_address(scope, %{label: "Depot", line1: "9 Dock Road"})
      {:ok, dock} = Address.create_address(scope, %{label: "Dock", line1: "3 Quay Lane"})
      {:ok, :attached} = Address.attach_to_company(scope, depot.id, 73)
      {:ok, :attached} = Address.attach_to_company(scope, dock.id, 73)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Another operator unlinks the address while this list still shows it:
      # the confirmation runs against a link that is already gone.
      :ok = Address.detach_from_company(scope, depot.id, 73)
      view |> element("#unlink-address-#{depot.id}") |> render_click()
      view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

      refute has_element?(view, "#unlink-address-confirm")
      refute has_element?(view, "#address-row-#{depot.id}")

      assert has_element?(
               view,
               "#company-addresses-panel-notice[role='status'][data-kind='info']",
               "That address is no longer linked."
             )

      # A request naming an address the refreshed list no longer holds.
      view |> element("#unlink-address-#{dock.id}") |> render_click(%{"id" => "#{depot.id}"})

      refute has_element?(view, "#unlink-address-confirm")

      assert has_element?(
               view,
               "#company-addresses-panel-notice[role='status'][data-kind='info']",
               "That address is no longer linked."
             )
    end

    test "the addresses panel shows a viewer the facts and the shared empty state", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "#addresses-table-empty", "No addresses linked.")

      assert has_element?(
               view,
               "#addresses-table-empty",
               "An operator who can edit companies can attach one."
             )

      {:ok, scope} = Tenancy.scope(41)
      {:ok, hq} = Address.create_address(scope, %{label: "Head Office", line1: "1 Market Street"})
      {:ok, :attached} = Address.attach_to_company(scope, hq.id, 73, %{priority: 3})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "#address-row-#{hq.id}", "Head Office")
      assert has_element?(view, "#address-row-#{hq.id}", "3")
      refute has_element?(view, "#address-priority-#{hq.id}[phx-hook='InlineEdit']")
      refute has_element?(view, "#edit-kinds-#{hq.id}")
      refute has_element?(view, "#toggle-primary-#{hq.id}")
      refute has_element?(view, "#unlink-address-#{hq.id}")
      refute has_element?(view, "#company-addresses-panel th", "Actions")
    end

    test "an in-place edit appears in the record history without a remount", %{conn: conn} do
      grant_capabilities!([
        "admin.company.list",
        "admin.company.view",
        "admin.company.update",
        "admin.audit.log.list"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")
      view |> element("#company-record-history-toggle") |> render_click()
      assert has_element?(view, "#company-record-history-empty")
      refute has_element?(view, "#company-record-history-panel", "Bilimbi Global")

      render_hook(view, "save_field", %{"id" => "73", "name" => "Bilimbi Global"})
      assert has_element?(view, "h1", "Bilimbi Global")

      # The panel was already open, so the trail follows the write on this
      # view without a remount and without opening history again.
      refute has_element?(view, "#company-record-history-empty")
      assert has_element?(view, "#company-record-history-toggle[aria-expanded='true']")
      assert has_element?(view, "#company-record-history-panel", "Updated")
      assert has_element?(view, "#company-record-history-panel", "Bilimbi Global")
    end

    test "edits the company facts in place and each reports its own outcome", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, type} =
        Company.create_legal_entity_type(scope!(), %{
          code: "SDN_BHD",
          name: "Sdn Bhd",
          is_active: true
        })

      CompanyFixtures.insert_company!(%{
        id: 76,
        tenant_id: 41,
        name: "Bilimbi Holdings",
        code: "bilimbi_holdings"
      })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # No edit mode: the heading carries no button and no modal exists; each
      # text fact is the shared in-place control.
      refute has_element?(view, "#edit-company-details-btn")
      refute has_element?(view, "#company-details-modal")

      for id <-
            ~w(company-name company-code company-legal-name company-registration-number company-tax-id company-email company-website) do
        assert has_element?(view, "##{id}[phx-hook='InlineEdit'][data-save-event='save_field']")
      end

      # Required columns are never blanked; the nullable ones may be.
      refute has_element?(view, "#company-name[data-allow-empty]")
      refute has_element?(view, "#company-code[data-allow-empty]")
      assert has_element?(view, "#company-legal-name[data-allow-empty]")
      assert has_element?(view, "#company-website[data-allow-empty]")

      # A text fact commits by itself and reports "Saved" on itself; the
      # header follows the stored value. Success does not flash.
      render_hook(view, "save_field", %{"id" => "73", "name" => "  Bilimbi Global  "})
      assert has_element?(view, "h1", "Bilimbi Global")
      assert has_element?(view, "#detail-name", "Bilimbi Global")
      assert has_element?(view, "#company-name-status[role='status']", "Saved")
      refute has_element?(view, "#flash-info")

      # "Saved" belongs to the most recent commit only.
      render_hook(view, "save_field", %{"id" => "73", "registration_number" => "REG-9999"})
      assert has_element?(view, "#company-registration-number-status", "Saved")
      refute has_element?(view, "#company-name-status")

      # A choice fact: the name is the trigger, the select appears on click,
      # commits on change and gives way to the read state. Status is not one:
      # it offers lifecycle operations instead ("Lifecycle" below).
      refute has_element?(view, "#company-status select")
      refute has_element?(view, "#company-status-display")

      view |> element("#company-legal-entity-type-display") |> render_click()

      view
      |> form("#company-legal-entity-type-form", %{"legal_entity_type_id" => to_string(type.id)})
      |> render_change()

      assert has_element?(view, "#company-legal-entity-type-display", "Sdn Bhd")

      view |> element("#company-jurisdiction-display") |> render_click()
      view |> form("#company-jurisdiction-form", %{"jurisdiction" => "MY"}) |> render_change()
      assert has_element?(view, "#company-jurisdiction-display", "Malaysia (MY)")

      view |> element("#company-parent-display") |> render_click()
      view |> form("#company-parent-form", %{"parent_id" => "76"}) |> render_change()
      assert has_element?(view, "#company-parent-display", "Bilimbi Holdings")
      assert has_element?(view, "#company-parent-status", "Saved")

      # Escape or leaving the select cancels without writing.
      view |> element("#company-parent-display") |> render_click()
      assert has_element?(view, "#company-parent-form")
      render_hook(view, "cancel_edit_field", %{})
      refute has_element?(view, "#company-parent-form")
      assert has_element?(view, "#company-parent-display", "Bilimbi Holdings")

      # The blank option clears a nullable relation.
      view |> element("#company-parent-display") |> render_click()
      view |> form("#company-parent-form", %{"parent_id" => ""}) |> render_change()
      assert has_element?(view, "#company-parent-display", "None")

      assert {:ok, stored} = Company.get_company(scope, 73)
      assert stored.name == "Bilimbi Global"
      assert stored.registration_number == "REG-9999"
      assert stored.status == "active"
      assert stored.legal_entity_type_id == type.id
      assert stored.jurisdiction == "MY"
      assert stored.parent_id == nil
    end

    test "a refused commit keeps the stored value on screen and reports the reason on the fact",
         %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)
      {:ok, _updated} = Company.update_company(scope, 73, %{email: "hq@bilimbi.test"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      render_hook(view, "save_field", %{"id" => "73", "email" => "not-an-address"})

      assert has_element?(
               view,
               "#company-email-status[role='alert']",
               ~s("not-an-address" was not saved: Email must be an email address.)
             )

      assert has_element?(view, "#detail-email", "hq@bilimbi.test")
      refute has_element?(view, "#company-email-status", "Saved")
      refute has_element?(view, "#flash-error")
      assert {:ok, %{email: "hq@bilimbi.test"}} = Company.get_company(scope, 73)

      # The hook never pushes a blanked required value; a forged one is
      # refused by the domain and the header keeps the stored name.
      render_hook(view, "save_field", %{"id" => "73", "name" => ""})
      assert has_element?(view, "#company-name-status[role='alert']", "Name can't be blank")
      assert has_element?(view, "h1", "Bilimbi Industries")

      # A long rejected value is cut so the reason stays on screen.
      too_long = String.duplicate("x", 300)
      render_hook(view, "save_field", %{"id" => "73", "tax_id" => too_long})

      assert has_element?(
               view,
               "#company-tax-id-status[role='alert']",
               "Tax ID should be at most 255 character(s)"
             )

      assert has_element?(view, "#company-tax-id-status", String.duplicate("x", 60) <> "…")
      refute has_element?(view, "#company-tax-id-status", String.duplicate("x", 61))

      # A forged choice outside the vocabulary is refused on its fact.
      render_change(view, "save_choice", %{"jurisdiction" => "ZZ"})

      assert has_element?(
               view,
               "#company-jurisdiction-status[role='alert']",
               ~s("ZZ" was not saved: Jurisdiction must be a valid country ISO code.)
             )

      refute has_element?(view, "#company-jurisdiction-display", "ZZ")

      # The alert stays until that fact is committed again -- a success
      # elsewhere does not clear it -- and then gives way to the new outcome.
      render_hook(view, "save_field", %{
        "id" => "73",
        "legal_name" => "Bilimbi Industries Sdn Bhd"
      })

      assert has_element?(view, "#company-email-status[role='alert']")
      assert has_element?(view, "#company-legal-name-status", "Saved")

      render_hook(view, "save_field", %{"id" => "73", "email" => "ops@bilimbi.test"})
      refute has_element?(view, "#company-email-status[role='alert']")
      assert has_element?(view, "#company-email-status", "Saved")
      assert has_element?(view, "#detail-email", "ops@bilimbi.test")
    end

    test "refuses in-place writes once the update capability is gone", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # A commit that did land, so the refusal below has a stale "Saved" to
      # clear.
      render_hook(view, "save_field", %{
        "id" => "73",
        "legal_name" => "Bilimbi Industries Sdn Bhd"
      })

      assert has_element?(view, "#company-legal-name-status[role='status']", "Saved")

      revoke_capability!(scope, "admin.company.update")

      render_hook(view, "save_field", %{"id" => "73", "name" => "Forged"})

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      # The refusal is the whole outcome: no "Saved" from the earlier commit
      # stands beside it.
      refute has_element?(view, "#company-legal-name-status")

      render_click(view, "request_lifecycle", %{"operation" => "archive"})
      render_submit(view, "apply_lifecycle", %{"reason" => "forged"})
      render_hook(view, "add_activity", %{"id" => "73", "activity" => "forged"})
      render_submit(view, "save_metadata", %{"metadata" => ~s({"forged": true})})
      render_change(view, "save_timezone", %{"timezone" => "Asia/Tokyo"})

      assert {:ok, stored} = Company.get_company(scope, 73)
      assert stored.name == "Bilimbi Industries"
      assert stored.legal_name == "Bilimbi Industries Sdn Bhd"
      assert stored.status == "active"
      assert stored.scope_activities in [nil, []]
      assert stored.metadata in [nil, %{}]
      assert has_element?(view, "#company-timezone-display", "Not configured (UTC)")
    end

    test "adds and removes business activities in place", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Adding is the shared in-place text control with an "Add activity"
      # trigger -- Belimbing's "+ Add" flow -- not a form with a button.
      assert has_element?(
               view,
               "#company-new-activity[phx-hook='InlineEdit'][data-save-event='add_activity']",
               "Add activity"
             )

      refute has_element?(view, "#add-activity-form")

      render_hook(view, "add_activity", %{"id" => "73", "activity" => " consulting "})
      assert has_element?(view, "#scope-activities-section", "consulting")
      assert has_element?(view, "#company-new-activity-status[role='status']", "Saved")
      refute has_element?(view, "#flash-info")

      render_hook(view, "add_activity", %{"id" => "73", "activity" => "training"})
      assert has_element?(view, "#scope-activities-section", "training")

      view |> element("#remove-activity-0") |> render_click()
      view |> element("#remove-activity-confirm-confirm") |> render_click()
      refute has_element?(view, "#scope-activities-section", "consulting")
      assert has_element?(view, "#scope-activities-section", "training")
      assert has_element?(view, "#company-new-activity-status", "Saved")

      {:ok, scope} = Tenancy.scope(41)
      assert {:ok, %{scope_activities: ["training"]}} = Company.get_company(scope, 73)
    end

    # `remove_activity` writes the company row immediately -- there is no
    # surrounding editor to cancel out of -- so the control confirms through the
    # shared dialog, which names the activity it is about to drop.
    test "confirms business activity removal and names the activity", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      render_hook(view, "add_activity", %{"id" => "73", "activity" => "consulting"})

      refute has_element?(view, "#remove-activity-0[data-confirm]")
      view |> element("#remove-activity-0") |> render_click()

      assert_modal_dialog(
        view,
        "remove-activity-confirm",
        "Business activity “consulting” will be removed from this company."
      )

      assert has_element?(view, "dialog#remove-activity-confirm[role='alertdialog']")

      assert has_element?(
               view,
               "#remove-activity-confirm-description",
               "The change is saved at once. The company's other activities are kept, and this one can be added again."
             )

      # Cancelling keeps the activity.
      view |> element("#remove-activity-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#remove-activity-confirm")
      assert has_element?(view, "#scope-activities-section", "consulting")

      # A confirm with nothing held is a stale click and changes nothing.
      render_hook(view, "remove_activity", %{})
      assert has_element?(view, "#scope-activities-section", "consulting")

      # Confirming removes it and reports on the fact itself.
      view |> element("#remove-activity-0") |> render_click()

      assert has_element?(
               view,
               "#remove-activity-confirm-confirm[phx-disable-with='Removing…']",
               "Remove"
             )

      view |> element("#remove-activity-confirm-confirm") |> render_click()
      refute has_element?(view, "#remove-activity-confirm")
      refute has_element?(view, "#scope-activities-section", "consulting")
      assert has_element?(view, "#company-new-activity-status", "Saved")

      {:ok, scope} = Tenancy.scope(41)
      assert {:ok, %{scope_activities: nil}} = Company.get_company(scope, 73)
    end

    test "edits, validates, and clears metadata JSON in place", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The read state opens the shared textarea editor in place.
      assert has_element?(
               view,
               "#company-metadata-editor-display[aria-label='Company metadata JSON']"
             )

      refute has_element?(view, "#company-metadata-editor-input")

      view |> element("#company-metadata-editor-display") |> render_click()

      assert has_element?(view, "dd#company-metadata #company-metadata-editor-input[rows='5']")
      assert has_element?(view, "#company-metadata-editor-input[phx-mounted]")

      # A refusal reports beside the fact and leaves its submitted text open
      # for correction.
      render_hook(view, "save_metadata", %{"metadata" => "invalid-json-text"})

      assert has_element?(
               view,
               "#company-metadata-editor-status[role='alert']",
               ~s("invalid-json-text" was not saved: Metadata must be a JSON object.)
             )

      assert has_element?(view, "#company-metadata-editor-input", "invalid-json-text")
      refute has_element?(view, "#flash-error")

      render_hook(view, "save_metadata", %{
        "metadata" => ~s({"founded": 2020, "tier": "enterprise"})
      })

      refute has_element?(view, "#company-metadata-editor-input")

      assert has_element?(
               view,
               "dd#company-metadata #company-metadata-editor-display",
               "enterprise"
             )

      assert has_element?(view, "#company-metadata-editor-status[role='status']", "Saved")
      refute has_element?(view, "#flash-info")

      # Cancel restores the read state without writing.
      view |> element("#company-metadata-editor-display") |> render_click()
      render_hook(view, "cancel_edit_metadata", %{})
      refute has_element?(view, "#company-metadata-editor-input")
      assert has_element?(view, "#company-metadata-editor-display", "enterprise")

      # Applying an empty document clears it.
      view |> element("#company-metadata-editor-display") |> render_click()
      render_hook(view, "save_metadata", %{"metadata" => ""})
      assert has_element?(view, "#company-metadata-editor-display", "—")
      assert has_element?(view, "#company-metadata-editor-status", "Saved")

      {:ok, scope} = Tenancy.scope(41)
      assert {:ok, %{metadata: nil}} = Company.get_company(scope, 73)
    end

    test "commits the default timezone on change and reports on the fact", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The read state is the trigger; no select stands beside the facts.
      assert has_element?(view, "#company-timezone-display", "Not configured (UTC)")
      refute has_element?(view, "#company-timezone-card select")
      assert has_element?(view, "#company-timezone-card", "No timezone is configured")

      view |> element("#company-timezone-display") |> render_click()

      assert has_element?(
               view,
               "#company-timezone-form input#company-timezone-select[role='combobox']"
             )

      view
      |> form("#company-timezone-form", %{"timezone" => "Asia/Kuala_Lumpur"})
      |> render_change()

      refute has_element?(view, "#company-timezone-form")
      assert has_element?(view, "#company-timezone-display", "Asia/Kuala_Lumpur")
      assert has_element?(view, "#company-timezone-status[role='status']", "Saved")
      refute has_element?(view, "#flash-info")
      refute has_element?(view, "#company-timezone-card", "No timezone is configured")

      # A forged value outside the IANA database is refused on the fact.
      render_change(view, "save_timezone", %{"timezone" => "Mars/Olympus"})

      assert has_element?(
               view,
               "#company-timezone-status[role='alert']",
               ~s("Mars/Olympus" was not saved: Default Timezone must be a valid IANA timezone.)
             )

      assert has_element?(view, "#company-timezone-display", "Asia/Kuala_Lumpur")

      view |> element("#company-timezone-display") |> render_click()
      view |> form("#company-timezone-form", %{"timezone" => ""}) |> render_change()
      assert has_element?(view, "#company-timezone-display", "Not configured (UTC)")
      assert has_element?(view, "#company-timezone-status", "Saved")
      assert has_element?(view, "#company-timezone-card", "No timezone is configured")
    end

    test "an unset company names the tenant-level zone its dates resolve to", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, _} =
        Settings.put("localization.timezone", "Asia/Kuala_Lumpur", SettingsScope.tenant(41))

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(
               view,
               "#company-timezone-display",
               "Not configured (Asia/Kuala_Lumpur)"
             )

      refute has_element?(view, "#company-timezone-display", "UTC")

      assert has_element?(
               view,
               "#company-timezone-card",
               "Dates and times will display in Asia/Kuala_Lumpur until a timezone is set."
             )

      refute has_element?(view, "#company-timezone-card", "display in UTC")
    end

    test "an unset company under an unconvertible tenant zone names UTC", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      SettingsFixtures.put_stored_value!(
        "localization.timezone",
        "Mars/Olympus",
        SettingsScope.tenant(41)
      )

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "#company-timezone-display", "Not configured (UTC)")
      refute has_element?(view, "#company-timezone-display", "Mars/Olympus")

      assert has_element?(
               view,
               "#company-timezone-card",
               "Dates and times will display in UTC until a timezone is set."
             )
    end

    # A refusal is the page's remaining flash, and the host hands every event
    # the refreshed scope, so the panel's controls vanish with the grant: no
    # dialog can open over the flash, and a restored grant brings the controls
    # back at the next event.
    test "a refused write withholds the panel's controls until the grant returns", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")
      assert has_element?(view, "#btn-open-attach-address")

      revoke_capability!(scope, "admin.company.update")

      render_hook(view, "save_field", %{"id" => "73", "name" => "Forged"})

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      refute has_element?(view, "#btn-open-attach-address")
      refute has_element?(view, "#btn-open-create-address")

      grant_capabilities!(["admin.company.update"])
      render_hook(view, "cancel_edit_field", %{})

      assert has_element?(view, "#btn-open-attach-address")
      view |> element("#btn-open-attach-address") |> render_click()
      assert_modal_dialog(view, "attach-address-modal", "Attach Address")
      refute has_element?(view, "#flash-error")
    end

    test "creates and attaches a new address through the company.addresses panel", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # The address behaviour now lives in the core/address-owned panel, reached
      # by manifest key; its events are phx-targeted to the component.
      view |> element("#btn-open-create-address") |> render_click()
      assert_modal_dialog(view, "company-create-address-modal", "Create & Attach Address")

      view
      |> form("#create-attach-address-form",
        address: %{
          "label" => "Head Office",
          "line1" => "1 Market Street",
          "locality" => "Kuala Lumpur",
          "country_iso" => "MY"
        }
      )
      |> render_submit()

      assert has_element?(view, "#company-addresses-panel", "Head Office")

      assert has_element?(
               view,
               "#company-addresses-panel-notice",
               "Address created and attached."
             )

      # A completed write is a success notice, announced politely, and the user
      # can dismiss it.
      assert has_element?(
               view,
               ~s(#company-addresses-panel-notice[role="status"][data-kind="success"])
             )

      view |> element("#company-addresses-panel-notice-dismiss") |> render_click()
      refute has_element?(view, "#company-addresses-panel-notice")

      {:ok, scope} = Tenancy.scope(41)
      {:ok, attached} = Bilimbi.Core.Address.list_company_attached_addresses(scope, 73)
      assert Enum.any?(attached, &(&1.label == "Head Office"))
    end

    test "a forged create-and-attach after grant revocation writes nothing", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Open the create modal while still authorized, so the form is in the DOM.
      view |> element("#btn-open-create-address") |> render_click()
      assert has_element?(view, "#create-attach-address-form")

      # Revoke the write capability. No LiveView event fires, so the form persists.
      {:ok, scope} = Tenancy.scope(41)

      grant =
        Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
        |> Map.fetch!(:entries)
        |> Enum.find(&(&1.capability == "admin.company.update"))

      assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

      # Forge the create submit against the still-rendered form. The panel
      # re-authorizes live per write (#610), so it refuses.
      view
      |> form("#create-attach-address-form",
        address: %{
          "label" => "Forged HQ",
          "line1" => "9 Forge Road",
          "locality" => "Kuala Lumpur",
          "country_iso" => "MY"
        }
      )
      |> render_submit()

      # The refusal is announced assertively from inside the still-open dialog,
      # because the page behind a modal dialog is inert.
      assert has_element?(
               view,
               ~s(dialog#company-create-address-modal #company-addresses-panel-notice[role="alert"][data-kind="error"]),
               "You do not have permission to edit companies."
             )

      # No attachment and no address row: the write never reached the store.
      {:ok, attached} = Bilimbi.Core.Address.list_company_attached_addresses(scope, 73)
      refute Enum.any?(attached, &(&1.label == "Forged HQ"))

      {:ok, all_addresses} = Bilimbi.Core.Address.list_addresses(scope)
      refute Enum.any?(all_addresses, &(&1.label == "Forged HQ"))
    end

    test "hides write controls when actor lacks admin.company.update", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      refute has_element?(view, "#company-details-card [phx-hook='InlineEdit']")
      refute has_element?(view, "#company-status button")
      assert has_element?(view, "#company-status", "Active")
      refute has_element?(view, "#company-new-activity")
      refute has_element?(view, "#company-metadata-editor-display")
      refute has_element?(view, "#company-timezone-display")
      refute has_element?(view, "#btn-open-create-address")
      refute has_element?(view, "#btn-open-attach-address")
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

  describe "Lifecycle" do
    setup do
      grant_capabilities!(["admin.company.list", "admin.company.view", "admin.company.update"])
      :ok
    end

    test "the status row offers only the operations the company may undergo", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      # Active: suspend or archive, in that order, and no select.
      assert has_element?(view, "#company-status", "Active")
      assert has_element?(view, "#company-suspend", "Suspend")
      assert has_element?(view, "#company-archive", "Archive")
      refute has_element?(view, "#company-activate")
      refute has_element?(view, "#company-reactivate")
      refute has_element?(view, "#company-status select")
      refute has_element?(view, "#company-status-final")

      # A forged operation the status does not offer opens nothing.
      render_click(view, "request_lifecycle", %{"operation" => "reactivate"})
      refute has_element?(view, "#company-lifecycle-modal")
      render_click(view, "request_lifecycle", %{"operation" => "drop table"})
      refute has_element?(view, "#company-lifecycle-modal")
      render_submit(view, "apply_lifecycle", %{"reason" => "nothing pending"})
      assert Company.get_company(scope!(), 73) |> elem(1) |> Map.fetch!(:status) == "active"
    end

    test "suspending leads with the consequence, records the reason and reports once", %{
      conn: conn
    } do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      view |> element("#company-suspend") |> render_click()

      assert has_element?(
               view,
               "dialog#company-lifecycle-modal h2",
               "Bilimbi Industries will be suspended."
             )

      assert has_element?(view, "#company-lifecycle-modal-description", "Reactivating")
      assert has_element?(view, "#company-lifecycle-form textarea#company-lifecycle-reason")
      assert has_element?(view, "#company-lifecycle-cancel", "Cancel")
      assert has_element?(view, "#company-lifecycle-confirm", "Suspend")

      # Cancel keeps the data as it is.
      view |> element("#company-lifecycle-cancel") |> render_click()
      refute has_element?(view, "#company-lifecycle-modal")
      assert has_element?(view, "#company-status", "Active")

      view |> element("#company-suspend") |> render_click()

      view
      |> form("#company-lifecycle-form", %{"reason" => "  Unpaid invoices  "})
      |> render_submit()

      # The dialog closes, the badge and the offered operations follow the
      # stored status, and the completed write flashes success.
      refute has_element?(view, "#company-lifecycle-modal")
      assert has_element?(view, "#company-status", "Suspended")
      assert has_element?(view, "header .flex", "Suspended")
      assert has_element?(view, "#company-reactivate", "Reactivate")
      assert has_element?(view, "#company-archive", "Archive")
      refute has_element?(view, "#company-suspend")
      assert has_element?(view, "#flash-success", "Suspended Bilimbi Industries.")

      scope = scope!()
      assert {:ok, %{status: "suspended"}} = Company.get_company(scope, 73)

      {:ok, actions} = Audit.list_actions(scope)
      assert [action] = Enum.filter(actions, &(&1.event == "company.suspended"))
      assert action.actor_type == "user"
      assert action.actor_id == 91
      assert action.company_id == 73
      assert action.is_retained
      assert action.payload["summary"] == "Suspended company “Bilimbi Industries”"
      assert action.payload["context"]["reason"] == "Unpaid invoices"
      assert action.payload["context"]["from_status"] == "active"
      assert action.payload["context"]["to_status"] == "suspended"
      assert action.url =~ "/companies/73"

      # Reactivating is the inverse, with no reason this time.
      view |> element("#company-reactivate") |> render_click()
      view |> form("#company-lifecycle-form", %{"reason" => ""}) |> render_submit()
      assert has_element?(view, "#company-status", "Active")
      assert has_element?(view, "#flash-success", "Reactivated Bilimbi Industries.")
      {:ok, actions} = Audit.list_actions(scope)
      assert [reactivated] = Enum.filter(actions, &(&1.event == "company.reactivated"))
      assert reactivated.payload["context"]["reason"] == nil
    end

    test "archiving states that it is final and leaves nothing to offer", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      view |> element("#company-archive") |> render_click()

      assert has_element?(
               view,
               "dialog#company-lifecycle-modal h2",
               "Bilimbi Industries will be archived."
             )

      assert has_element?(
               view,
               "#company-lifecycle-modal-description",
               "Archiving is final: an archived company cannot be reactivated."
             )

      assert has_element?(view, "#company-lifecycle-confirm", "Archive")
      view |> form("#company-lifecycle-form", %{"reason" => "Wound up"}) |> render_submit()

      refute has_element?(view, "#company-lifecycle-modal")
      assert has_element?(view, "#company-status", "Archived")
      assert has_element?(view, "#company-status-final", "Archiving is final.")
      refute has_element?(view, "#company-status button")
      assert has_element?(view, "#flash-success", "Archived Bilimbi Industries.")

      scope = scope!()
      assert {:ok, %{status: "archived"}} = Company.get_company(scope, 73)
      {:ok, actions} = Audit.list_actions(scope)
      assert [action] = Enum.filter(actions, &(&1.event == "company.archived"))
      assert action.payload["context"]["reason"] == "Wound up"

      # Nothing leaves archived, even by a forged event.
      render_click(view, "request_lifecycle", %{"operation" => "reactivate"})
      refute has_element?(view, "#company-lifecycle-modal")
      assert {:ok, %{status: "archived"}} = Company.get_company(scope, 73)
    end

    test "an overlong reason is refused in the open dialog and nothing is written", %{
      conn: conn
    } do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      view |> element("#company-suspend") |> render_click()
      too_long = String.duplicate("x", Company.lifecycle_reason_max_length() + 1)
      view |> form("#company-lifecycle-form", %{"reason" => too_long}) |> render_submit()

      # The dialog stays open with its own copy of the flash, because the
      # page behind it is inert; the typed reason is kept for correction.
      assert has_element?(
               view,
               "#company-lifecycle-modal #company-lifecycle-modal-flash-error",
               "at most #{Company.lifecycle_reason_max_length()} characters"
             )

      assert has_element?(view, "#company-lifecycle-reason", String.slice(too_long, 0, 50))
      assert {:ok, %{status: "active"}} = Company.get_company(scope!(), 73)
      {:ok, actions} = Audit.list_actions(scope!())
      refute Enum.any?(actions, &String.starts_with?(&1.event, "company."))
    end

    test "a status changed by someone else is shown and the stale operation is refused", %{
      conn: conn
    } do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      view |> element("#company-suspend") |> render_click()

      # A colleague archives it while the dialog is open.
      scope = scope!() |> Bilimbi.Base.Tenancy.Authentication.sign_in(91, 73)
      assert {:ok, _} = Company.archive_company(scope, 73)

      view |> form("#company-lifecycle-form", %{"reason" => ""}) |> render_submit()

      refute has_element?(view, "#company-lifecycle-modal")
      assert has_element?(view, "#company-status", "Archived")
      assert has_element?(view, "#flash-error", "it is now archived")
      assert {:ok, %{status: "archived"}} = Company.get_company(scope!(), 73)
    end
  end

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end
end
