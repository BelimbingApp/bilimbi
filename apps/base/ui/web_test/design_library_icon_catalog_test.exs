defmodule BilimbiWeb.DesignLibraryIconCatalogTest do
  @moduledoc """
  The Graphic page's icon catalogue: every registry name as a tile, a filter
  over them, an empty result that says how to recover, and copy feedback that
  follows what the browser reported.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.IconRegistry
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    grant_capabilities!("admin.system.design-library.view")

    {:ok, view, _html} = conn |> log_in_as() |> live("/system/design-library/graphic")
    %{view: view}
  end

  defp filter(view, search) do
    view
    |> element("#icon-catalog-filters")
    |> render_change(%{"icon_filters" => %{"search" => search}})
  end

  defp copied(view, name, copied?) do
    view
    |> element("#icon-catalog")
    |> render_hook("icon-copied", %{"text" => name, "copied" => copied?})
  end

  test "every registry name is a copyable tile, grouped by how a screen reaches it", %{
    view: view
  } do
    total = IconRegistry.catalog() |> Enum.map(&length(&1.icons)) |> Enum.sum()

    assert has_element?(view, "#icon-catalog[phx-hook='ClipboardCopy']")
    assert has_element?(view, "#icon-catalog-count", "#{total} icons")

    assert has_element?(
             view,
             "#icon-catalog-glyphs #icon-tile-bilimbi-pin[data-copy-text='bilimbi-pin']"
           )

    assert has_element?(view, "#icon-catalog-actions #icon-tile-create", "hero-plus")
    refute has_element?(view, "#icon-catalog-empty")
  end

  test "the filter narrows the tiles by name or by the Heroicon they resolve to", %{view: view} do
    filter(view, "  ARCHIVE ")

    assert has_element?(view, "#icon-tile-archive")
    assert has_element?(view, "#icon-tile-unarchive")
    refute has_element?(view, "#icon-tile-create")
    refute has_element?(view, "#icon-catalog-glyphs")
    assert has_element?(view, "#icon-catalog-count", "2 of ")

    filter(view, "hero-clock")

    assert has_element?(view, "#icon-tile-clock")
    assert has_element?(view, "#icon-tile-history")
    refute has_element?(view, "#icon-tile-archive")
  end

  test "a filter that matches nothing says so and clears back to every icon", %{view: view} do
    filter(view, "zzz-no-such-icon")

    assert has_element?(view, "#icon-catalog-empty", "No icons match “zzz-no-such-icon”")

    assert has_element?(
             view,
             "#icon-catalog-empty",
             "Clear the filter to see every registered icon."
           )

    refute has_element?(view, "#icon-catalog [data-copy-text]")

    view |> element("#icon-catalog-clear") |> render_click()

    refute has_element?(view, "#icon-catalog-empty")
    assert has_element?(view, "#icon-tile-create")
    assert has_element?(view, "#icon-catalog-search[value='']")
  end

  test "a copied name is confirmed on its tile and announced", %{view: view} do
    refute has_element?(view, "[id$='-copied']")

    copied(view, "create", true)

    assert has_element?(
             view,
             "#icon-catalog-status[role='status']",
             "Copied “create” to the clipboard."
           )

    assert has_element?(view, "#icon-tile-create-copied", "Copied")
    refute has_element?(view, "#icon-catalog-copy-failed")

    copied(view, "delete", true)

    assert has_element?(view, "#icon-tile-delete-copied")
    refute has_element?(view, "#icon-tile-create-copied")
  end

  test "a copy the browser refused is reported, not confirmed", %{view: view} do
    copied(view, "bilimbi-pin", false)

    assert has_element?(
             view,
             "#icon-catalog-copy-failed[role='alert']",
             "The browser did not allow copying “bilimbi-pin”."
           )

    refute has_element?(view, "#icon-tile-bilimbi-pin-copied")
    refute has_element?(view, "#icon-catalog-status", "Copied")
  end

  test "a copy report for a name the catalogue never offered changes nothing", %{view: view} do
    copied(view, "<script>", true)

    refute has_element?(view, "#icon-catalog-status", "Copied")
    refute has_element?(view, "[id$='-copied']")
  end
end
