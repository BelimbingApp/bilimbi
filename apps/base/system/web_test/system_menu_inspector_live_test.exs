defmodule BilimbiWeb.SystemMenuInspectorLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/menu-inspector")
  end

  test "redirects away without admin.system.menu-inspector.view", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/menu-inspector")
  end

  test "lists contributed items with source and marks its nav row current", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    assert has_element?(view, "h1", "Menu Inspector")
    assert has_element?(view, "#menu-inspector", "admin.system.info")
    assert has_element?(view, "#menu-inspector", "/system/info")
    assert has_element?(view, "#menu-inspector", "base/system")
    assert has_element?(view, "#nav-admin-system-menu-inspector[aria-current='page']")
  end

  test "search narrows by id, label, or source", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    view
    |> form("#menu-inspector-filters", %{"filters" => %{"search" => "menu-inspector"}})
    |> render_change()

    assert has_element?(view, "#menu-inspector", "admin.system.menu-inspector")
    refute has_element?(view, "#menu-inspector", "admin.system.info")
    assert has_element?(view, "#menu-inspector-pagination-summary", "results")
    refute has_element?(view, "#menu-inspector-pagination-page-2")
    refute render(view) =~ "Page 1 of 1"
  end

  # The installed platform contributes more menu items than one 25-row page, so
  # the unfiltered listing is the complement of the single-page guard above.
  test "a listing holding more than one page still names the page it is on", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    assert has_element?(view, "#menu-inspector-pagination-summary", "Showing 1 to 25 of")
    assert has_element?(view, "#menu-inspector-pagination-previous[disabled]")
    assert has_element?(view, "#menu-inspector-pagination-page-1[aria-current='page']")
    assert has_element?(view, "#menu-inspector-pagination-next")

    view |> element("#menu-inspector-pagination-next") |> render_click()

    assert_patch(view, ~p"/system/menu-inspector?page=2&page_size=25")
    assert has_element?(view, "#menu-inspector-pagination-page-2[aria-current='page']")
    assert has_element?(view, "#menu-inspector-pagination-previous")
    assert has_element?(view, "#menu-inspector-pagination-next[disabled]")
  end

  test "source filter narrows by contributing module", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    view
    |> form("#menu-inspector-filters", %{"filters" => %{"source" => "base/authz"}})
    |> render_change()

    assert has_element?(view, "#menu-inspector", "admin.authz")
    refute has_element?(view, "#menu-inspector", "admin.system.info")
  end

  test "search, source, and page size round-trip through the URL", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    view
    |> form("#menu-inspector-filters", %{
      "filters" => %{"search" => "authz", "source" => "base/authz"}
    })
    |> render_change()

    filtered = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert filtered["page"] == "1"
    assert filtered["page_size"] == "25"
    assert filtered["search"] == "authz"
    assert filtered["source"] == "base/authz"

    {:ok, reloaded, _html} =
      conn
      |> log_in_as()
      |> live(~p"/system/menu-inspector?page=1&page_size=25&search=authz&source=base/authz")

    assert has_element?(reloaded, "#menu-inspector-search[value='authz']")
    assert has_element?(reloaded, "#menu-source-filter option[value='base/authz'][selected]")
    assert has_element?(reloaded, "#menu-inspector", "admin.authz")
    refute has_element?(reloaded, "#menu-inspector", "admin.system.info")

    reloaded
    |> form("#menu-inspector-pagination-page-size-form", %{"filters" => %{"perPage" => "100"}})
    |> render_change()

    sized_query =
      assert_patch(reloaded) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert sized_query["page"] == "1"
    assert sized_query["page_size"] == "100"
    assert sized_query["search"] == "authz"
    assert sized_query["source"] == "base/authz"

    {:ok, sized, _html} =
      conn
      |> log_in_as()
      |> live(~p"/system/menu-inspector?page=1&page_size=100&search=authz&source=base/authz")

    assert has_element?(
             sized,
             "#menu-inspector-pagination-page-size option[value='100'][selected]"
           )

    assert has_element?(sized, "#menu-inspector-search[value='authz']")
    refute has_element?(sized, "#menu-inspector", "admin.system.info")
  end
end
