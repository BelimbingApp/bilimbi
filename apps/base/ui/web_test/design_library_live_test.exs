defmodule BilimbiWeb.DesignLibraryLiveTest do
  @moduledoc """
  End-to-end tests for the Design Library under `/system/design-library`.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @view_cap "admin.system.design-library.view"
  @areas [
    {"/system/design-library", "#foundations"},
    {"/system/design-library/components", "#components"},
    {"/system/design-library/design-spec", "#specifications"},
    {"/system/design-library/graphic", "#graphics"}
  ]
  @family_menu_labels [
    "A Foundations",
    "B Page structure",
    "C Navigation and links",
    "D Actions",
    "E Inputs",
    "F Interaction patterns",
    "G Feedback and states",
    "H Overlays",
    "I Data display",
    "J Composite patterns",
    "K Graphics"
  ]
  @paths Enum.map(@areas, &elem(&1, 0))

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp family_menu_labels(view) do
    family_menu_lines(view, "first-child")
  end

  defp family_menu_descriptions(view) do
    family_menu_lines(view, "last-child")
  end

  defp family_menu_lines(view, position) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(
      "#component-secondary-menu nav[aria-label='Component families'] a > span > span:#{position}"
    )
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp open(conn, path) do
    grant_capabilities!(@view_cap)
    conn |> log_in_as() |> live(path)
  end

  defp area_text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  test "all Design Library areas require authentication", %{conn: conn} do
    for path <- @paths do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
    end
  end

  test "redirects away when the actor lacks admin.system.design-library.view", %{conn: conn} do
    for path <- @paths do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(path)
    end
  end

  test "Theme is the canonical entry and shows the visual foundations", %{conn: conn} do
    {:ok, view, html} = open(conn, "/system/design-library")

    assert html =~ "Theme"
    assert html =~ "Instrument Sans"
    assert has_element?(view, "#foundations")
    refute has_element?(view, "#decision-t01")
    assert has_element?(view, "#theme-surfaces-lines", "Surfaces & Lines")
    assert has_element?(view, "#theme-line-thickness", "Hairline")
    assert has_element?(view, "#theme-line-thickness", "1px")
    assert has_element?(view, "#theme-identity", "Identity & Action")
    assert has_element?(view, "#theme-feedback", "Feedback")
    assert has_element?(view, "#theme-typography", "Typography")
    assert has_element?(view, "#theme-shape", "Shape & Density")
    assert has_element?(view, "#theme-text", "Strong ink")
    assert has_element?(view, "#theme-text", "Inverse ink")
    assert has_element?(view, "#theme-navigation-text", "Link")
    assert has_element?(view, "#theme-navigation-text", "Muted")
    assert has_element?(view, "#theme-navigation-text", "Active")
    assert has_element?(view, "#theme-line-contrast", "Each surface below is paired")
    assert has_element?(view, "#theme-structure", "High-contrast line")
    assert has_element?(view, "#theme-structure", "Low-contrast line")
    assert has_element?(view, "#theme-primary-line", "Primary line")
    assert has_element?(view, "#theme-selection-line", "Selection line")
    assert has_element?(view, "#theme-brand-line", "Brand line")
    assert has_element?(view, "#theme-success-line", "Success line")
    assert has_element?(view, "#theme-warning-line", "Warning line")
    assert has_element?(view, "#theme-danger-line", "Danger line")
    refute has_element?(view, "#theme-colour")
    refute has_element?(view, "#components")
    assert has_element?(view, "#nav-admin-system-design-library-theme[aria-current='page']")
  end

  test "Components lists the eleven catalog families without resolved alternatives", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    for number <- 1..6 do
      refute has_element?(view, "#decision-c0#{number}")
    end

    assert has_element?(view, "#component-secondary-menu nav[aria-label='Component families']")

    # The menu is the parity capability catalog's eleven families, in catalog
    # order. The A-K prefixes make that sequence identical to the alphabetical
    # ascending order DESIGN.md "Ordering" requires, so both are asserted.
    labels = family_menu_labels(view)
    assert labels == @family_menu_labels
    assert labels == Enum.sort(labels)

    # Nine families are reviewed on this page. Each entry carries its own family
    # label and lands on the section that owns that family's specimens, so a
    # swapped target fails rather than sending the reviewer to a sibling.
    for {slug, family} <- [
          {"page-structure", "Page structure"},
          {"navigation-links", "Navigation and links"},
          {"actions", "Actions"},
          {"inputs", "Inputs"},
          {"interaction-patterns", "Interaction patterns"},
          {"feedback-states", "Feedback and states"},
          {"overlays", "Overlays"},
          {"data-display", "Data display"},
          {"composite-patterns", "Composite patterns"}
        ] do
      assert has_element?(view, "#component-menu-#{slug}[href='#component-#{slug}']", family)
      assert has_element?(view, "#component-#{slug}")
    end

    # Foundations and Graphics already have their own areas, so the menu points
    # at them instead of showing a second copy here.
    assert has_element?(
             view,
             "#component-menu-foundations[href='/system/design-library']",
             "Foundations"
           )

    assert has_element?(
             view,
             "#component-menu-graphics[href='/system/design-library/graphic']",
             "Graphics"
           )

    # Overlays reviews the shared modal dialog, so its section owns that
    # specimen rather than standing empty.
    assert has_element?(view, "#component-overlays #component-modal")

    # The application shell is LAY-02, so it sits inside Page structure and
    # keeps its own deep link. The menu entry is nested under B rather than
    # sitting between B and C as a flat sibling, so the nav's own children are
    # the eleven families and the A-K sequence above describes every one of them.
    assert has_element?(view, "#component-page-structure #component-shell")
    assert has_element?(view, "#component-secondary-menu a[href='#component-shell']")

    refute has_element?(
             view,
             "#component-secondary-menu nav[aria-label='Component families'] > #component-menu-shell"
           )

    assert has_element?(
             view,
             "#component-secondary-menu nav[aria-label='Component families'] > div > #component-menu-page-structure + #component-menu-shell"
           )

    refute has_element?(view, "#component-catalog")
    assert has_element?(view, "#design-library-input-guidance", "Choice guidance")
    assert has_element?(view, "#design-library-input-live-state", "Live state")
    assert has_element?(view, "#component-icon-button", "Compact icon actions")
    assert has_element?(view, "#component-actions button[aria-busy='true'][disabled]", "Saving…")
    assert has_element?(view, "#design-library-icon-button-disabled[disabled]:not([aria-busy])")
    assert has_element?(view, "#design-library-icon-button-busy[aria-busy='true'][disabled]")
    assert has_element?(view, "#example-nav[aria-label='Example menu']")
    assert has_element?(view, "#example-nav #nav-example-companies", "Companies")
    assert has_element?(view, "#example-nav [data-nav-branch='example.system']")
    assert has_element?(view, "#example-nav [aria-current='page']", "Design Library")
    assert has_element?(view, "#app-sidebar.app-nav-rail")
    assert has_element?(view, "#example-nav.app-nav-rail")
    assert has_element?(view, "#app-sidebar [data-nav-pin]")
    refute has_element?(view, "#example-nav [data-nav-pin]")
    assert has_element?(view, "#example-tabs[aria-label='Example views']")
    assert has_element?(view, "#example-tabs [aria-current='page']", "Overview")
    assert has_element?(view, "#component-radio-group")
    assert has_element?(view, "#component-radio-group-system[checked]")
    assert has_element?(view, "#design-library-radio-disabled[disabled]")
    assert has_element?(view, "#design-library-radio-disabled-system[checked][disabled]")
    assert has_element?(view, "#design-library-radio-locked[aria-label='Data region'][disabled]")
    assert has_element?(view, "#design-library-multi-select-plain[aria-label='Optional roles']")

    assert has_element?(
             view,
             "#design-library-page-stage #design-library-page-list.max-w-7xl",
             "wide for filters and tables"
           )

    assert has_element?(
             view,
             "#design-library-page-stage #design-library-page-form.max-w-2xl",
             "narrow for focused entry"
           )

    assert has_element?(
             view,
             "#design-library-page-stage #design-library-page-detail.max-w-7xl",
             "the list width, for a record or dashboard"
           )

    assert has_element?(
             view,
             "#design-library-header-default",
             "Title, subtitle, and trailing action"
           )

    assert has_element?(
             view,
             "#design-library-header-title-action",
             "Title action without a trailing action"
           )

    assert has_element?(
             view,
             "#design-library-header-title-action button.size-6[aria-label='Edit company']"
           )

    for kind <- ~w(error warning success info) do
      assert has_element?(view, "#component-flash #design-library-flash-#{kind}")
    end

    assert has_element?(view, "#component-flash", "Save failed")
    assert has_element?(view, "#component-flash", "preference status line")

    assert has_element?(
             view,
             "#component-connection-banners #design-library-connection-client-error:not([hidden]):not([phx-disconnected])",
             "Connection interrupted"
           )

    assert has_element?(
             view,
             "#component-connection-banners #design-library-connection-server-error:not([hidden]):not([phx-disconnected])",
             "Server unavailable"
           )

    assert has_element?(view, "#flash-group #connection-client-error[hidden][phx-disconnected]")
    assert has_element?(view, "#flash-group #connection-server-error[hidden][phx-disconnected]")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[phx-disconnected]")
           |> Enum.count() == 2

    assert has_element?(view, "#design-library-card-titled .border-b h3", "Company profile")
    refute has_element?(view, "#design-library-card-untitled h3")

    assert has_element?(
             view,
             "#design-library-card-boundary",
             "no loading, empty, error, or disabled"
           )

    assert has_element?(
             view,
             "#design-library-list-boundary",
             "no loading, empty, or error state"
           )

    for area <- ~w(components component-composite-patterns component-feedback-states) do
      assert has_element?(view, "##{area}")
    end

    refute has_element?(view, "#foundations")
    refute has_element?(view, "#graphics")
    refute has_element?(view, "#specifications")

    for component <- ~w(header button badge alert table inputs datetime filter-toolbar) do
      assert has_element?(view, "#component-#{component}")
    end

    assert has_element?(view, "#sample-table", "Acme Holdings")
    assert has_element?(view, "#sample-table", "Example Company 10")
    assert has_element?(view, "#nav-admin-system-design-library-components[aria-current='page']")
  end

  test "the filter toolbar specimen shows every control type under one rule", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "#filter-toolbar-full label.sr-only", "Search example companies")
    assert has_element?(view, "#filter-toolbar-full label.sr-only", "Status filter")
    assert has_element?(view, "#filter-toolbar-full label.sr-only", "Start date")
    assert has_element?(view, "#filter-toolbar-full .hero-magnifying-glass")
    assert has_element?(view, "#design-library-filter-full-start-date + p", "UTC")

    view
    |> form("#design-library-filter-full", %{"toolbar_full" => %{"search" => "Acme"}})
    |> render_change()

    assert has_element?(view, "#design-library-filter-full-search[value='Acme']")

    assert has_element?(view, "#filter-toolbar-search-only .hero-magnifying-glass")
    refute has_element?(view, "#filter-toolbar-search-only select")

    view
    |> form("#design-library-filter-search-only", %{"toolbar_search" => %{"search" => "Globex"}})
    |> render_change()

    assert has_element?(view, "#design-library-filter-search-only-search[value='Globex']")
  end

  test "the action link and timestamp specimens show each way they are called", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(
             view,
             "#design-library-action-link[href='/system/design-library']:not([data-method])"
           )

    assert has_element?(
             view,
             "#design-library-action-link-submit[href='/admin/impersonate/leave'][data-method='post']",
             "Stop viewing as another user"
           )

    assert has_element?(view, "#design-library-date-time-second", "14:30:00")
    refute has_element?(view, "#design-library-date-time", "14:30:00")
  end

  test "Components input examples update their visible state", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    view
    |> form("#design-library-fields", %{
      "sample" => %{
        "text_field" => "Bilimbi Holdings",
        "search_field" => "company",
        "select_field" => "advanced",
        "roles" => ["operator"],
        "required_roles" => ["admin", "reviewer"],
        "plain_roles" => ["admin", "operator"],
        "example_interests" => ["platform", "billing"],
        "checkbox_field" => "true",
        "radio_field" => "dark",
        "datetime_field" => "2026-08-26T14:30"
      }
    })
    |> render_change()

    assert has_element?(view, "#design-library-input-live-state", "Bilimbi Holdings")
    assert has_element?(view, "#design-library-input-live-state", "operator")
    assert has_element?(view, "#design-library-input-live-state", "dark")

    assert has_element?(view, "#design-library-multi-select", "1 role selected")
    assert has_element?(view, "#design-library-multi-select-required", "2 roles selected")
    assert has_element?(view, "#design-library-multi-select-plain", "2 options selected")
    assert has_element?(view, "#example_interests", "2 interests selected")
  end

  test "both pagination specimens update their own rows and page size", %{conn: conn} do
    for {pagination, table, other_table} <- [
          {"component-pagination", "sample-table", "design-library-pattern-table"},
          {"design-library-pattern-pagination", "design-library-pattern-table", "sample-table"}
        ] do
      {:ok, view, _html} = open(conn, "/system/design-library/components")

      assert has_element?(view, "##{pagination}-previous[disabled]")
      assert has_element?(view, "##{table} tr:nth-child(25)")
      refute has_element?(view, "##{table} tr:nth-child(26)")
      view |> element("##{pagination}-next") |> render_click()

      assert has_element?(view, "##{pagination}-summary", "Showing 26 to 50 of 120 results")
      assert has_element?(view, "##{table}", "Example Company 26")
      refute has_element?(view, "##{table}", "Acme Holdings")
      assert has_element?(view, "##{other_table}", "Acme Holdings")

      view |> element("##{pagination}-page-5") |> render_click()
      assert has_element?(view, "##{pagination}-next[disabled]")
      assert has_element?(view, "##{pagination}-summary", "Showing 101 to 120 of 120 results")
      assert has_element?(view, "##{table} tr:nth-child(20)")
      refute has_element?(view, "##{table} tr:nth-child(21)")

      for size <- [50, 100, 300, 25] do
        view
        |> form("##{pagination}-page-size-form", %{"filters" => %{"perPage" => to_string(size)}})
        |> render_change()

        count = min(size, 120)

        assert has_element?(
                 view,
                 "##{pagination}-summary",
                 "Showing 1 to #{count} of 120 results"
               )

        assert has_element?(view, "##{table} tr:nth-child(#{count})")
        refute has_element?(view, "##{table} tr:nth-child(#{count + 1})")
        assert has_element?(view, "##{other_table} tr:nth-child(25)")
        refute has_element?(view, "##{other_table} tr:nth-child(26)")
      end
    end
  end

  test "pattern search resets its page and recovers from empty results", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")
    view |> element("#design-library-pattern-pagination-next") |> render_click()

    view
    |> form("#design-library-pattern-search", %{"pattern" => %{"search" => "Globex"}})
    |> render_change()

    assert has_element?(view, "#design-library-pattern-table", "Globex Corporation")

    assert has_element?(
             view,
             "#design-library-pattern-pagination-summary",
             "Showing 1 to 1 of 1 results"
           )

    refute has_element?(view, "#design-library-pattern-pagination-next")
    assert has_element?(view, "#sample-table", "Acme Holdings")

    view
    |> form("#design-library-pattern-search", %{"pattern" => %{"search" => "no matching company"}})
    |> render_submit()

    assert has_element?(view, "#design-library-pattern-empty")
    refute has_element?(view, "#design-library-pattern-pagination-summary")
    assert has_element?(view, "#design-library-pattern-pagination-page-size")

    view
    |> form("#design-library-pattern-search", %{"pattern" => %{"search" => ""}})
    |> render_change()

    refute has_element?(view, "#design-library-pattern-empty")

    assert has_element?(
             view,
             "#design-library-pattern-pagination-summary",
             "Showing 1 to 25 of 120 results"
           )
  end

  test "the canonical table searches, reports no match, and recovers", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")
    view |> element("#component-pagination-next") |> render_click()

    view
    |> form("#design-library-table-search", %{"sample_filters" => %{"search" => "Globex"}})
    |> render_change()

    assert has_element?(view, "#design-library-table-search .hero-magnifying-glass")
    assert has_element?(view, "#sample-table", "Globex Corporation")
    assert has_element?(view, "#component-pagination-summary", "Showing 1 to 1 of 1 results")
    refute has_element?(view, "#sample-table-empty")

    view
    |> form("#design-library-table-search", %{
      "sample_filters" => %{"search" => "no such company"}
    })
    |> render_submit()

    assert has_element?(view, "#sample-table-empty", "No companies match")
    assert has_element?(view, "#sample-table-empty", "no such company")

    view |> element("#sample-clear-search") |> render_click()

    refute has_element?(view, "#sample-table-empty")
    assert has_element?(view, "#sample-table", "Acme Holdings")
    assert has_element?(view, "#component-pagination-summary", "Showing 1 to 25 of 120 results")
  end

  test "the canonical table sorts by its headings and starts each sort on page one", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "#sample-sort-updated")
    assert has_element?(view, "th[aria-sort='ascending'] #sample-sort-name")
    assert has_element?(view, "th[aria-sort='none'] #sample-sort-updated")
    assert has_element?(view, "#sample-table tr:first-child", "Acme Holdings")
    assert has_element?(view, "#sample-table tr:nth-child(2)", "Example Company 10")
    refute has_element?(view, "#sample-table", "Globex Corporation")

    view |> element("#sample-sort-updated") |> render_click()
    assert has_element?(view, "th[aria-sort='descending'] #sample-sort-updated")
    assert has_element?(view, "th[aria-sort='none'] #sample-sort-name")
    assert has_element?(view, "#sample-table tr:first-child", "Acme Holdings")
    assert has_element?(view, "#sample-table tr:nth-child(3)", "Initech LLC")

    view |> element("#sample-sort-updated") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #sample-sort-updated")
    assert has_element?(view, "#sample-table tr:first-child", "Example Company 120")

    view |> element("#sample-sort-name") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #sample-sort-name")

    view |> element("#sample-sort-name") |> render_click()
    assert has_element?(view, "th[aria-sort='descending'] #sample-sort-name")
    assert has_element?(view, "#sample-table tr:first-child", "Initech LLC")
    assert has_element?(view, "#sample-table tr:nth-child(2)", "Globex Corporation")

    view |> element("#component-pagination-page-5") |> render_click()
    assert has_element?(view, "#component-pagination-summary", "Showing 101 to 120")
    view |> element("#sample-sort-status") |> render_click()
    assert has_element?(view, "#component-pagination-summary", "Showing 1 to 25")
    assert has_element?(view, "th[aria-sort='ascending'] #sample-sort-status")
    assert has_element?(view, "#sample-table tr:first-child", "active")
    assert has_element?(view, "#sample-table tr:nth-child(25)")
    refute has_element?(view, "#sample-table tr:nth-child(26)")
    assert has_element?(view, "#design-library-pattern-table", "Acme Holdings")
  end

  test "no Design Library area renders a parity catalog identifier", %{conn: conn} do
    for {path, area} <- @areas do
      {:ok, view, _html} = open(conn, path)

      refute area_text(view, area) =~ ~r/\b[A-Z]{3,4}-\d{2}\b/,
             "#{path} renders a catalog identifier"
    end

    {:ok, components, _html} = open(conn, "/system/design-library/components")
    assert area_text(components, "#component-shell h3") == "Application shell"

    descriptions = family_menu_descriptions(components)
    assert length(descriptions) == length(@family_menu_labels)

    for description <- descriptions do
      refute description =~ ~r/^[A-Z][A-Z0-9]*\s*·/,
             "the component family menu still leads a description with a catalog code: #{description}"
    end

    {:ok, spec, _html} = open(conn, "/system/design-library/design-spec")
    assert area_text(spec, "#spec-shell h2") == "Application shell"
  end

  test "example actions preview fictional facts without linking to business records", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    refute has_element?(view, "#sample-table a")
    view |> element("#sample-preview-1") |> render_click()
    assert has_element?(view, "#flash-info", "Acme Holdings")
    assert has_element?(view, "#flash-info", "Example only")
    assert has_element?(view, "#components")
  end

  test "preview pagination clamps stale pages and ignores invalid values", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    for {event, pagination} <- [
          {"sample", "component-pagination"},
          {"pattern", "design-library-pattern-pagination"}
        ] do
      render_click(view, "#{event}-page", %{"page" => "999"})
      assert has_element?(view, "##{pagination}-summary", "Showing 101 to 120 of 120 results")
      render_click(view, "#{event}-page", %{"page" => "invalid"})
      assert has_element?(view, "##{pagination}-summary", "Showing 101 to 120 of 120 results")
      render_change(view, "#{event}-page-size", %{"filters" => %{"perPage" => "5"}})
      assert has_element?(view, "##{pagination}-summary", "Showing 1 to 25 of 120 results")
    end
  end

  test "Graphic shows the Bilimbi mark and icons in current use", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/graphic")

    assert has_element?(view, "#graphics")
    assert has_element?(view, "#graphic-mark img[alt='Bilimbi']")
    assert has_element?(view, "#graphic-icons")
    assert has_element?(view, "#graphic-icon-variants", "Outline")
    assert has_element?(view, "#graphic-icon-variants", "Solid")
    assert has_element?(view, "#graphic-icon-variants", "Mini")

    assert has_element?(
             view,
             "#graphic-icon-variants",
             "Size and color are set where the icon is used"
           )

    refute has_element?(view, "#components")
    assert has_element?(view, "#nav-admin-system-design-library-graphic[aria-current='page']")
  end

  # Each accepted choice keeps its Design Spec number as a stable anchor id so
  # tests and links can reach the card, but the rendered heading carries only
  # the statement: the number is a working reference, not something an
  # operator reads (DESIGN.md "Write for humans").
  @design_spec_cards [
    {"spec-t01", "Theme contrast stays distinct"},
    {"spec-d01", "Colour has meaning"},
    {"spec-d02", "Type stays quiet"},
    {"spec-c01", "Compact fields always win"},
    {"spec-c02", "Focus uses the lively brand accent"},
    {"spec-c03", "Destructive actions stay calm"},
    {"spec-c04", "Filters use an open toolbar"},
    {"spec-c05", "Familiar row actions use icons"},
    {"spec-c06", "Icon size follows context"},
    {"spec-d03", "Width follows the work"},
    {"spec-d04", "Data stays compact"},
    {"spec-d05", "Copy is for the user"},
    {"spec-d06", "Every state is designed"}
  ]

  test "Design Spec contains only accepted choices grouped by purpose", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/design-spec")

    assert has_element?(view, "#specifications")
    assert has_element?(view, "#accepted-design")
    assert has_element?(view, "#spec-components", "Components")

    for {id, statement} <- @design_spec_cards do
      assert has_element?(view, "##{id} h4", statement)
    end

    assert has_element?(view, "#spec-theme", "Theme")
    assert has_element?(view, "#spec-structure-data", "Structure and data")
    assert has_element?(view, "#spec-experience", "Experience")
    refute has_element?(view, "#open-design-decisions")
    refute has_element?(view, "#components")
    assert has_element?(view, "#nav-admin-system-design-library-design-spec[aria-current='page']")
  end

  test "Design Spec headings carry the statement, not its number", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/design-spec")

    for {id, _statement} <- @design_spec_cards do
      code = id |> String.replace_prefix("spec-", "") |> String.upcase()

      assert has_element?(view, "##{id} h4")
      refute has_element?(view, "##{id}", code)
    end
  end

  test "keeps development metadata out of every Design Library screen", %{conn: conn} do
    for path <- @paths do
      {:ok, _view, html} = open(conn, path)

      # A catalog or decision code leading a statement, such as `D01 ·` or
      # `FND-01 ·`, is a working reference and never operator-facing copy.
      refute html =~ ~r/\b[A-Z]{1,4}-?\d{2,3}\s*(·|—|–|:)\s/

      refute html =~ "bilimbi/default"
      refute html =~ "Git working tree"
      refute html =~ "Belimbing provenance"
      refute html =~ "Contract Rule"
      refute html =~ "#287"
      refute html =~ "coding agent"
    end
  end

  test "handles interactive button clicks on Components", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "button", "Clicked: 0")

    view
    |> element("button", "Clicked: 0")
    |> render_click()

    assert has_element?(view, "button", "Clicked: 1")
  end

  test "opens each modal dialog width and closes it again", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    refute has_element?(view, "#design-library-modal")

    view |> element("#design-library-open-modal") |> render_click()
    assert_modal_dialog(view, "design-library-modal", "Rename example company")

    view |> element("#design-library-modal button", "Cancel") |> render_click()
    refute has_element?(view, "#design-library-modal")

    view |> element("#design-library-open-wide-modal") |> render_click()
    assert_modal_dialog(view, "design-library-wide-modal", "Edit example company")

    view |> form("#design-library-wide-modal-form") |> render_submit()
    refute has_element?(view, "#design-library-wide-modal")
  end

  test "walks the confirmation flow: consequence, cancel, in flight, success, failure, recovery",
       %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "#component-overlays #component-confirm-dialog")
    refute has_element?(view, "#design-library-confirm")
    refute has_element?(view, "#design-library-confirm-delete-sole[data-confirm]")

    # Entry: a demoted danger action opens the dialog, which leads with the
    # consequence and says what cannot be undone.
    view |> element("#design-library-confirm-delete-sole") |> render_click()

    assert_modal_dialog(
      view,
      "design-library-confirm",
      "Legal entity type “Sole Proprietorship” will be deleted."
    )

    assert has_element?(view, "dialog#design-library-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#design-library-confirm-description",
             "It can no longer be chosen for a company. This cannot be undone."
           )

    # Cancel keeps the example.
    view |> element("#design-library-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#design-library-confirm")
    assert has_element?(view, "#design-library-confirm-row-sole", "Sole Proprietorship")

    # In flight: the confirm shows its working label while LiveView holds it.
    assert has_element?(
             view,
             "#component-confirm-dialog #design-library-confirm-in-flight[aria-busy='true'][disabled]",
             "Deleting…"
           )

    # Success: the row is gone and the outcome says so.
    view |> element("#design-library-confirm-delete-sole") |> render_click()

    assert has_element?(
             view,
             "#design-library-confirm-confirm[phx-disable-with='Deleting…']",
             "Delete"
           )

    view |> element("#design-library-confirm-confirm", "Delete") |> render_click()

    refute has_element?(view, "#design-library-confirm")
    refute has_element?(view, "#design-library-confirm-row-sole")
    assert has_element?(view, "#design-library-confirm-outcome", "Legal entity type deleted.")

    # Failure and recovery: the refused example stays, the message says why
    # and what to do, and the examples can be restored.
    view |> element("#design-library-confirm-delete-llc") |> render_click()

    assert_modal_dialog(
      view,
      "design-library-confirm",
      "Legal entity type “Limited Liability Company” will be deleted."
    )

    view |> element("#design-library-confirm-confirm") |> render_click()

    refute has_element?(view, "#design-library-confirm")
    assert has_element?(view, "#design-library-confirm-row-llc", "Limited Liability Company")

    assert has_element?(
             view,
             "#design-library-confirm-outcome",
             "Limited Liability Company was not deleted: 3 companies still use it. " <>
               "Change those companies' legal entity type first."
           )

    view |> element("#design-library-confirm-reset", "Restore examples") |> render_click()
    assert has_element?(view, "#design-library-confirm-row-sole", "Sole Proprietorship")
    refute has_element?(view, "#design-library-confirm-outcome")
  end

  test "keeps inline editing interactive without persisting business data", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "#design-library-inline-edit", "Editable entity value")

    view
    |> element("#design-library-inline-edit")
    |> render_hook("preview-inline-edit", %{"value" => "Reviewed preview"})

    assert has_element?(view, "#design-library-inline-edit", "Reviewed preview")
    assert render(view) =~ "Preview value updated."
  end
end
