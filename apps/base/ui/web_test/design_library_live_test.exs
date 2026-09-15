defmodule BilimbiWeb.DesignLibraryLiveTest do
  @moduledoc """
  End-to-end tests for the Design Library under `/system/design-library`.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @view_cap "admin.system.design-library.view"
  @paths [
    "/system/design-library",
    "/system/design-library/components",
    "/system/design-library/design-spec",
    "/system/design-library/graphic"
  ]

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn, path) do
    grant_capabilities!(@view_cap)
    conn |> log_in_as() |> live(path)
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

  test "Components uses a grouped secondary menu without resolved alternatives", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    for number <- 1..6 do
      refute has_element?(view, "#decision-c0#{number}")
    end

    assert has_element?(view, "#component-secondary-menu nav[aria-label='Component sections']")
    assert has_element?(view, "#component-menu-structure", "Structure")
    assert has_element?(view, "#component-menu-controls", "Controls")
    assert has_element?(view, "#component-menu-communication", "Communication")
    assert has_element?(view, "#component-menu-workflows", "Workflows")

    for section <- ~w(structure inputs actions feedback states data patterns) do
      assert has_element?(
               view,
               "#component-secondary-menu a[href='#component-#{section}']"
             )
    end

    refute has_element?(view, "#component-catalog")
    assert has_element?(view, "#component-input-guidance", "Choice guidance")
    assert has_element?(view, "#component-input-live-state", "Live state")
    assert has_element?(view, "#component-icon-button", "Compact icon actions")

    assert has_element?(
             view,
             "#component-page-stage #component-page-list.max-w-7xl",
             "wide for filters and tables"
           )

    assert has_element?(
             view,
             "#component-page-stage #component-page-form.max-w-2xl",
             "narrow for focused entry"
           )

    assert has_element?(
             view,
             "#component-page-stage #component-page-detail.max-w-4xl",
             "medium for a record or dashboard"
           )

    assert has_element?(view, "#component-header-default", "Title, subtitle, and trailing action")

    assert has_element?(
             view,
             "#component-header-title-action",
             "Title action without a trailing action"
           )

    assert has_element?(
             view,
             "#component-header-title-action button.size-6[aria-label='Edit company']"
           )

    assert has_element?(view, "#component-flash > .transform-gpu > #design-library-flash")
    assert has_element?(view, "#component-flash > .transform-gpu > #design-library-flash-error")
    assert has_element?(view, "#component-flash", "Save failed")
    assert has_element?(view, "#component-card-titled .border-b h3", "Company profile")
    refute has_element?(view, "#component-card-untitled h3")
    assert has_element?(view, "#component-card-boundary", "no loading, empty, error, or disabled")
    assert has_element?(view, "#component-list-boundary", "no loading, empty, or error state")

    for area <- ~w(components component-patterns component-states) do
      assert has_element?(view, "##{area}")
    end

    refute has_element?(view, "#foundations")
    refute has_element?(view, "#graphics")
    refute has_element?(view, "#specifications")

    for component <- ~w(header button badge alert table inputs datetime) do
      assert has_element?(view, "#component-#{component}")
    end

    assert has_element?(view, "#sample-table", "Acme Holdings")
    assert has_element?(view, "#sample-table", "Globex Corporation")
    assert has_element?(view, "#nav-admin-system-design-library-components[aria-current='page']")
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
        "checkbox_field" => "true",
        "radio_field" => "dark",
        "datetime_field" => "2026-08-26T14:30"
      }
    })
    |> render_change()

    assert has_element?(view, "#component-input-live-state", "Bilimbi Holdings")
    assert has_element?(view, "#component-input-live-state", "operator")
    assert has_element?(view, "#component-input-live-state", "dark")
  end

  test "both pagination specimens update their own rows and page size", %{conn: conn} do
    for {pagination, table, other_table} <- [
          {"design-library-pagination", "sample-table", "design-library-pattern-table"},
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
          {"sample", "design-library-pagination"},
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

  test "Design Spec contains only accepted choices grouped by purpose", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/design-spec")

    assert has_element?(view, "#specifications")
    assert has_element?(view, "#accepted-design")
    assert has_element?(view, "#spec-d01")
    assert has_element?(view, "#spec-d06")
    assert has_element?(view, "#spec-t01", "Theme contrast stays distinct")
    assert has_element?(view, "#spec-components", "Components")

    for number <- 1..6 do
      assert has_element?(view, "#spec-c0#{number}", "C0#{number}")
    end

    assert has_element?(view, "#spec-theme", "Theme")
    assert has_element?(view, "#spec-structure-data", "Structure and data")
    assert has_element?(view, "#spec-experience", "Experience")
    refute has_element?(view, "#open-design-decisions")
    refute has_element?(view, "#components")
    assert has_element?(view, "#nav-admin-system-design-library-design-spec[aria-current='page']")
  end

  test "keeps development metadata out of every Design Library screen", %{conn: conn} do
    for path <- @paths do
      {:ok, _view, html} = open(conn, path)

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
