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

  test "Components presents numbered choices before the full component inventory", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn, "/system/design-library/components")

    assert has_element?(view, "#development-review")

    for number <- 1..6 do
      assert has_element?(view, "#decision-c0#{number}", "C0#{number}")
    end

    assert has_element?(view, "#component-decisions-forms", "Forms")
    assert has_element?(view, "#component-decisions-actions", "Actions")
    assert has_element?(view, "#component-decisions-lists", "Operational lists")

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

  test "Graphic shows the Bilimbi mark and icons in current use", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/system/design-library/graphic")

    assert has_element?(view, "#graphics")
    assert has_element?(view, "#graphic-mark img[alt='Bilimbi']")
    assert has_element?(view, "#graphic-icons")
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
