defmodule Bilimbi.Base.Tiling.WorkspaceLiveTest do
  @moduledoc """
  The tiled workspace through the real host: the sidebar's tile control and
  the `open` address it points at, the picker, the tree in the URL, every
  tile operation the hook and the tile menu push, the permission refusal in
  place of a frame, the chromeless refusal to nest, and saved layouts.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tiling.SavedLayouts
  alias Bilimbi.Base.Tiling.SharedLayouts
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @companies "admin.company.list"
  @settings_scope Settings.Scope.user(91, 73, 41)

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn, path \\ "/workspace") do
    grant_capabilities!(@companies)
    conn |> log_in_as() |> live(path)
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/workspace")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/workspace/orders")
  end

  test "an empty workspace opens the picker and is the sidebar's current page", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#nav-workspace[aria-current='page']")
    # Every navigable row carries "Open in a tile" beside its pin, except
    # the workspace's own row.
    assert has_element?(
             view,
             "#nav-tile-admin-company[data-nav-tile='/companies'][href='/companies'][aria-label='Open Companies in a tile']"
           )

    assert has_element?(view, "#nav-pin-admin-company")
    refute has_element?(view, "#nav-tile-workspace")
    assert has_element?(view, "#workspace-empty-state", "No pages open")
    assert has_element?(view, "#workspace-add-page")
    assert_modal_dialog(view, "workspace-picker", "Add a page")
    assert has_element?(view, "#workspace-pick-admin-company", "Companies")
    refute has_element?(view, "#workspace-pick-workspace")
  end

  test "the picker lists only pages this account may open", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/workspace")

    refute has_element?(view, "#workspace-pick-admin-company")
    assert has_element?(view, "#workspace-picker-empty", "No pages to add")
  end

  test "adding pages splits the focused tile and writes the tree into the URL", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> element("#workspace-pick-admin-company") |> render_click()
    assert_patch(view, "/workspace?t=%2Fcompanies")

    assert has_element?(
             view,
             "#tile-t1[data-focused='true'] iframe#tile-t1-page[src^='/companies?ws=']"
           )

    assert has_element?(view, "#tile-t1-header-title", "/companies")
    refute has_element?(view, "#workspace-picker")

    view |> element("#workspace-add-page") |> render_click()
    view |> element("#workspace-pick-admin-company") |> render_click()
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")

    assert has_element?(view, "#tile-t2[data-focused='true']")
    assert has_element?(view, "#tile-t1[data-focused='false']")

    assert has_element?(
             view,
             "#split-s3[role='separator'][aria-orientation='vertical'][data-split='s3']"
           )

    # A path that is not in the picker is refused, whatever the client sends.
    render_hook(view, "add-tile", %{"path" => "/users"})
    refute has_element?(view, "#tile-t3")
  end

  test "open= tiles the page in the address next to the page it names, and drops itself",
       %{conn: conn} do
    # From a page: `t` is that page, and the clicked page takes the right
    # half. A full page load of that address lands on the resulting tree.
    grant_capabilities!(@companies)
    conn = log_in_as(conn)

    {:ok, view, _html} =
      conn
      |> live("/workspace?t=/companies?page=2&open=/companies")
      |> follow_redirect(conn, "/workspace?t=h.5%28%2Fcompanies%3Fpage%3D2%2C%2Fcompanies%29")

    assert has_element?(view, "#tile-t1 iframe[src^='/companies?page=2&ws=']")
    assert has_element?(view, "#tile-t2 iframe[src^='/companies?ws=']")
    assert has_element?(view, "#split-s3[aria-orientation='vertical']")

    # From the workspace: the same shape as a patch, and the largest tile is
    # halved, the right half first and then the left, so four pages are
    # quadrants.
    render_patch(view, "/workspace?t=h.5(/companies?page=2,/companies)&open=/companies")

    assert_patch(
      view,
      "/workspace?t=h.5%28%2Fcompanies%3Fpage%3D2%2Cv.5%28%2Fcompanies%2C%2Fcompanies%29%29"
    )

    assert has_element?(
             view,
             "#workspace-tiles [data-focused='true'][data-place*='left: 50.0%'][data-place*='top: 50.0%']"
           )

    render_patch(
      view,
      "/workspace?t=h.5(/companies?page=2,v.5(/companies,/companies))&open=/companies"
    )

    assert_patch(
      view,
      "/workspace?t=h.5%28v.5%28%2Fcompanies%3Fpage%3D2%2C%2Fcompanies%29%2Cv.5%28%2Fcompanies%2C%2Fcompanies%29%29"
    )

    assert has_element?(
             view,
             "#workspace-tiles [data-focused='true'][data-place*='left: 0.0%'][data-place*='top: 50.0%']"
           )

    # The frames already on screen kept their elements through every patch.
    assert has_element?(view, "#tile-t1-page[src^='/companies?page=2&ws=']")
    assert has_element?(view, "#workspace[data-tile-count='4']")
  end

  test "open= with no tree starts the workspace with that page, in a saved layout too",
       %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=/companies")
    render_patch(view, "/workspace?open=/companies")
    assert_patch(view, "/workspace?t=%2Fcompanies")
    assert has_element?(view, "#workspace[data-tile-count='1']")
    assert has_element?(view, "#tile-t2-page[src^='/companies?ws='][data-tile-frame='t2']")
    refute has_element?(view, "#workspace-picker")

    {:ok, _} = SavedLayouts.save(@settings_scope, "Orders", "/companies")
    {:ok, view, _html} = open(conn, "/workspace/orders")
    render_patch(view, "/workspace/orders?open=/companies")
    assert_patch(view, "/workspace/orders?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#tile-t2-page")
  end

  test "open= tiles any page a tile may show, such as a pinned record", %{conn: conn} do
    grant_capabilities!("admin.company.view")
    {:ok, view, _html} = open(conn, "/workspace?t=/companies")

    render_patch(view, "/workspace?t=/companies&open=/companies/73?tab=users")
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%2F73%3Ftab%3Dusers%29")
    assert has_element?(view, "#tile-t2-page[src^='/companies/73?tab=users&ws=']")
  end

  test "open= refuses a page this account may not open, and the workspace", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=/companies")

    render_patch(view, "/workspace?t=/companies&open=/users")
    assert_patch(view, "/workspace?t=%2Fcompanies")
    assert render(view) =~ "/users cannot be opened in a tile."
    refute has_element?(view, "#tile-t2")

    render_patch(view, "/workspace?t=/companies&open=/workspace")
    assert_patch(view, "/workspace?t=%2Fcompanies")
    refute has_element?(view, "#tile-t2")

    render_patch(view, "/workspace?t=/companies&open=/workspace/orders")
    assert_patch(view, "/workspace?t=%2Fcompanies")
    refute has_element?(view, "#tile-t2")
  end

  test "a workspace entered by tiling a page in place returns to the page at one tile",
       %{conn: conn} do
    {:ok, page, _html} = open(conn, "/companies")

    {:ok, view, _html} =
      live_redirect(page, to: "/workspace?t=/companies?page=2&inplace=1&open=/companies")

    assert has_element?(view, "#workspace[data-tile-count='2']")

    render_hook(view, "close-tile", %{"id" => "t2"})
    assert_redirect(view, "/companies?page=2")

    # The marker survives a full load and every patch, so a refresh or a
    # reconnect still returns to the page.
    conn = log_in_as(build_conn())

    {:ok, view, _html} =
      conn
      |> live("/workspace?t=/companies?page=2&inplace=1&open=/companies")
      |> follow_redirect(
        conn,
        "/workspace?t=h.5%28%2Fcompanies%3Fpage%3D2%2C%2Fcompanies%29&inplace=1"
      )

    render_hook(view, "resize-split", %{"id" => "s3", "ratio" => 0.3})
    assert_patch(view, "/workspace?t=h.3%28%2Fcompanies%3Fpage%3D2%2C%2Fcompanies%29&inplace=1")

    {:ok, view, _html} =
      live(conn, "/workspace?t=h.3%28%2Fcompanies%3Fpage%3D2%2C%2Fcompanies%29&inplace=1")

    render_hook(view, "close-tile", %{"id" => "t1"})
    assert_redirect(view, "/companies")
  end

  test "saving an in-place workspace as a layout drops the marker", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,/companies)&inplace=1")

    view |> element("#workspace-open-layouts") |> render_click()

    view
    |> form("#workspace-save-form", %{"layout" => %{"label" => "Orders desk"}})
    |> render_submit()

    assert_patch(view, "/workspace/orders-desk")

    render_hook(view, "close-tile", %{"id" => "t2"})
    assert_patch(view, "/workspace/orders-desk?t=%2Fcompanies")
    assert has_element?(view, "#workspace[data-tile-count='1']")
  end

  test "a workspace from the picker or a saved layout keeps its one tile", %{conn: conn} do
    {:ok, view, _html} = open(conn)
    render_hook(view, "add-tile", %{"path" => "/companies"})
    render_hook(view, "add-tile", %{"path" => "/companies"})
    render_patch(view, "/workspace?t=h.5(/companies,/companies)&open=/companies")

    assert has_element?(view, "#workspace[data-tile-count='3']")
    for id <- ["t4", "t2"], do: render_hook(view, "close-tile", %{"id" => id})
    assert_patch(view, "/workspace?t=%2Fcompanies")
    assert has_element?(view, "#workspace[data-tile-count='1']")

    {:ok, _} = SavedLayouts.save(@settings_scope, "Orders", "h.5(/companies,/companies)")
    {:ok, view, _html} = open(conn, "/workspace/orders")

    render_hook(view, "close-tile", %{"id" => "t2"})
    assert_patch(view, "/workspace/orders?t=%2Fcompanies")
    assert has_element?(view, "#workspace[data-tile-count='1']")
  end

  test "the tree in the URL reproduces the screen, and a bad one opens empty", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=v.6(/companies,/companies)")

    assert has_element?(view, "#tile-t1[data-place*='height: 60.0%']")
    assert has_element?(view, "#tile-t2[data-place*='top: 60.0%']")
    assert has_element?(view, "#split-s3[aria-orientation='horizontal']")
    refute has_element?(view, "#workspace-picker")

    {:ok, view, html} = open(conn, "/workspace?t=h.5(/companies")

    assert html =~ "could not be read"
    assert has_element?(view, "#workspace-empty-state")
  end

  test "a tile the account may not open shows the refusal in place of the frame", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,v.5(/users,/nowhere))")

    assert has_element?(view, "#tile-t1-page")
    assert has_element?(view, "#tile-t2-forbidden", "You do not have permission to open /users.")
    refute has_element?(view, "#tile-t2-page")
    assert has_element?(view, "#tile-t3-unserved", "This page is not available")
  end

  test "an operator-only page is refused in place outside the platform-operator tenant",
       %{conn: conn} do
    CompanyFixtures.insert_tenant!(%{
      id: 51,
      name: "Ordinary tenant",
      is_platform_operator: false
    })

    CompanyFixtures.insert_company!(%{
      id: 83,
      tenant_id: 51,
      name: "Ordinary Co",
      code: "ordinary"
    })

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 83,
      name: "Nadia",
      email: "nadia@example.com"
    })

    grant_capabilities!(["admin.system.database-table.list"],
      tenant_id: 51,
      company_id: 83,
      user_id: 95
    )

    {:ok, view, _html} =
      conn
      |> log_in_as(session_user(%{"user_id" => 95, "company_id" => 83}))
      |> live("/workspace?t=/admin/system/database-queries")

    assert has_element?(view, "#tile-t1-forbidden")
    refute has_element?(view, "#tile-t1-page")

    grant_capabilities!("admin.system.database-table.list")
    {:ok, view, _html} = open(conn, "/workspace?t=/admin/system/database-queries")
    assert has_element?(view, "#tile-t1-page")
  end

  test "a tree naming another origin never becomes a tile", %{conn: conn} do
    for tree <- [
          "%2F%2Fevil.example%2Flogin",
          "h.5(/companies,%2F%2Fevil.example%2Flogin)",
          "https%3A%2F%2Fevil.example%2Flogin",
          "%2F%5Cevil.example%2Flogin",
          "%2F%09%2Fevil.example%2Flogin"
        ] do
      {:ok, view, html} = open(conn, "/workspace?t=" <> tree)

      assert html =~ "could not be read"
      assert has_element?(view, "#workspace-empty-state")
      refute has_element?(view, "[data-tile]")
    end

    {:ok, view, _html} = open(conn, "/workspace?t=/companies")
    render_hook(view, "tile-navigated", %{"id" => "t1", "path" => "//evil.example/login"})
    render_hook(view, "tile-navigated", %{"id" => "t1", "path" => "/\t/evil.example/login"})
    assert has_element?(view, "#tile-t1-page[src^='/companies?ws=']")

    entry = %{
      "slug" => "evil",
      "label" => "Evil",
      "layout" => "dwindle",
      "tree" => "%2F%09%2Fevil.example%2Flogin"
    }

    {:ok, _} = Settings.put("ui.workspace.layouts", [entry], @settings_scope)

    {:ok, view, html} = open(conn, "/workspace/evil")
    assert html =~ "could not be read"
    refute has_element?(view, "[data-tile]")
  end

  test "the picker opens at a current tile only, however the tree changed", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,/companies)")

    render_hook(view, "focus-tile", %{"id" => "t2"})
    render_hook(view, "open-picker", %{"id" => "t2"})
    render_patch(view, "/workspace?t=/companies")
    refute has_element?(view, "#tile-t2")

    view |> element("#workspace-pick-admin-company") |> render_click()
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#tile-t1")

    render_patch(view, "/workspace?t=/companies")
    render_hook(view, "open-picker", %{"id" => "t9"})
    view |> element("#workspace-pick-admin-company") |> render_click()
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
  end

  test "the tile menu and the hook's events operate the tree", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,/companies)")

    # Focus by direction, then swap with the neighbour in that direction.
    render_hook(view, "focus-tile", %{"id" => "t1"})
    render_hook(view, "focus-direction", %{"side" => "right"})
    assert has_element?(view, "#tile-t2[data-focused='true']")

    view |> element("#tile-t2-header-swap") |> render_click()
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#tile-t2[data-place*='left: 0.0%']")

    view |> element("#tile-t2-header-split") |> render_click()
    assert_patch(view, "/workspace?t=v.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#split-s3[aria-orientation='horizontal']")

    render_hook(view, "resize-split", %{"id" => "s3", "ratio" => 0.3})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#split-s3[data-place*='top: 30.0%']")

    render_hook(view, "nudge-split", %{"id" => "s3", "side" => "down"})
    assert_patch(view, "/workspace?t=v.35%28%2Fcompanies%2C%2Fcompanies%29")

    render_hook(view, "resize-step", %{"side" => "up"})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")

    render_hook(view, "move-tile", %{"id" => "t2", "side" => "down"})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#tile-t1[data-place*='top: 0.0%']")

    view |> element("#tile-t2-header-monocle") |> render_click()
    assert has_element?(view, "#workspace[data-monocle='true']")
    assert has_element?(view, "#tile-t2[data-place*='width: 100%']")
    assert has_element?(view, "#tile-t1[hidden]")
    refute has_element?(view, "#split-s3")
    assert has_element?(view, "#tile-t2-header-monocle", "Show every tile")

    view |> element("#tile-t2-header-close") |> render_click()
    assert_patch(view, "/workspace?t=%2Fcompanies")
    assert has_element?(view, "#workspace[data-tile-count='1']")
  end

  test "a tile dropped on another swaps the two, and the last of many closes in place",
       %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,v.5(/companies,/companies))")

    render_hook(view, "swap-tile", %{"id" => "t1", "with" => "t3"})

    assert_patch(
      view,
      "/workspace?t=h.5%28%2Fcompanies%2Cv.5%28%2Fcompanies%2C%2Fcompanies%29%29"
    )

    assert has_element?(view, "#tile-t3[data-place*='left: 0.0%'][data-place*='height: 100.0%']")
    assert has_element?(view, "#tile-t1[data-place*='top: 50.0%']")

    # A drop on an unknown tile, or on itself, changes nothing.
    render_hook(view, "swap-tile", %{"id" => "t1", "with" => "t9"})
    render_hook(view, "swap-tile", %{"id" => "t1", "with" => "t1"})
    assert has_element?(view, "#tile-t1[data-place*='top: 50.0%']")

    render_hook(view, "close-tile", %{"id" => "t2"})
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#workspace[data-tile-count='2']")
  end

  test "closing down to a tile the account may not open stays, with the refusal", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,/users)")

    render_hook(view, "close-tile", %{"id" => "t1"})
    assert_patch(view, "/workspace?t=%2Fusers")
    assert has_element?(view, "#tile-t2-forbidden")
  end

  test "a frame's report updates the tile's title and path without a history entry", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=/companies")

    render_hook(view, "tile-navigated", %{
      "id" => "t1",
      "path" => "/companies/department-types?page=2",
      "title" => "Department Types · Business application platform"
    })

    assert_patch(view, "/workspace?t=%2Fcompanies%2Fdepartment-types%3Fpage%3D2")
    assert has_element?(view, "#tile-t1-header-title", "Department Types")

    assert has_element?(
             view,
             "#tile-t1-header-open-alone[href='/companies/department-types?page=2']"
           )

    # An absolute URL or an unserved path never becomes a tile.
    render_hook(view, "tile-navigated", %{
      "id" => "t1",
      "path" => "https://example.test/x",
      "title" => "x"
    })

    render_hook(view, "tile-navigated", %{
      "id" => "t1",
      "path" => "//example.test/x",
      "title" => "x"
    })

    render_hook(view, "tile-navigated", %{"id" => "t1", "path" => "/nowhere", "title" => "x"})

    assert has_element?(
             view,
             "#tile-t1-header-open-alone[href='/companies/department-types?page=2']"
           )
  end

  test "the workspace holds as many tiles as the operator opens", %{conn: conn} do
    eight =
      "h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,/companies)))))))"

    {:ok, view, _html} = open(conn, "/workspace?t=#{eight}")

    assert has_element?(view, "#workspace[data-tile-count='8']")
    refute has_element?(view, "#workspace[data-max-tiles]")

    view |> element("#workspace-add-page") |> render_click()
    assert has_element?(view, "#workspace-picker", "Every tile is a live page")
    view |> element("#workspace-pick-admin-company") |> render_click()
    assert has_element?(view, "#workspace[data-tile-count='9']")
  end

  test "the workspace refuses to open inside a tile", %{conn: conn} do
    grant_capabilities!(@companies)

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> put_req_header("sec-fetch-dest", "iframe")
      |> live(~p"/workspace?t=/companies")

    assert has_element?(view, "#workspace-framed-state", "cannot open inside a tile")
    assert has_element?(view, "#workspace-framed-open[target='_top'][href='/workspace']")
    refute has_element?(view, "#workspace")
    refute has_element?(view, "#app-sidebar")
  end

  describe "saved layouts" do
    test "saving names the layout, gives it an address, and lists it", %{conn: conn} do
      {:ok, view, _html} = open(conn, "/workspace?t=h.5(/companies,/companies)")

      view |> element("#workspace-open-layouts") |> render_click()
      assert_modal_dialog(view, "workspace-layouts", "Saved layouts")
      assert has_element?(view, "#workspace-saved-layouts-empty", "No saved layouts")

      view
      |> form("#workspace-save-form", %{"layout" => %{"label" => "   "}})
      |> render_submit()

      assert has_element?(view, "#workspace-save-form", "Give the layout a name")

      view
      |> form("#workspace-save-form", %{"layout" => %{"label" => "Orders desk"}})
      |> render_submit()

      assert_patch(view, "/workspace/orders-desk")
      assert has_element?(view, "#tile-t1-page")

      assert [%{"slug" => "orders-desk", "tree" => "h.5(/companies,/companies)"}] =
               SavedLayouts.list(@settings_scope)

      {:ok, view, _html} = open(conn, "/workspace/orders-desk")
      assert has_element?(view, "#tile-t1-page")
      assert has_element?(view, "#tile-t2-page")

      view |> element("#workspace-open-layouts") |> render_click()
      assert has_element?(view, "#workspace-layout-orders-desk", "Orders desk")

      assert has_element?(
               view,
               "#workspace-layout-open-orders-desk[href='/workspace/orders-desk']"
             )

      assert has_element?(view, "#workspace-update-layout", "Update “Orders desk”")
    end

    test "an unknown address says so and opens the plain workspace", %{conn: conn} do
      grant_capabilities!(@companies)

      assert {:error, {:live_redirect, %{to: "/workspace", flash: flash}}} =
               conn |> log_in_as() |> live(~p"/workspace/nowhere")

      assert flash["error"] =~ "no saved layout called “nowhere”"
    end

    test "the default layout opens with the workspace, and rename, update and delete are self-service",
         %{conn: conn} do
      {:ok, _} = SavedLayouts.save(@settings_scope, "Orders", "/companies")
      {:ok, _} = SavedLayouts.save(@settings_scope, "People", "h.5(/companies,/companies)")

      {:ok, view, _html} = open(conn, "/workspace")
      view |> element("#workspace-open-layouts") |> render_click()
      view |> element("#workspace-layout-set-default-orders") |> render_click()
      assert has_element?(view, "#workspace-layout-default-orders", "Default")
      assert SavedLayouts.default_slug(@settings_scope) == "orders"

      grant_capabilities!(@companies)

      assert {:error, {:live_redirect, %{to: "/workspace/orders"}}} =
               conn |> log_in_as() |> live(~p"/workspace")

      {:ok, view, _html} = open(conn, "/workspace/orders")
      assert has_element?(view, "#tile-t1-page[src^='/companies?ws=']")

      # The keyboard's 2 opens the second saved layout.
      render_hook(view, "open-layout", %{"n" => 2})
      assert_patch(view, "/workspace/people")

      {:ok, view, _html} = open(conn, "/workspace/orders")
      view |> element("#workspace-add-page") |> render_click()
      view |> element("#workspace-pick-admin-company") |> render_click()
      assert_patch(view, "/workspace/orders?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")

      view |> element("#workspace-open-layouts") |> render_click()
      view |> element("#workspace-update-layout") |> render_click()

      assert {:ok, %{"tree" => "h.5(/companies,/companies)"}} =
               SavedLayouts.fetch(@settings_scope, "orders")

      render_hook(view, "rename-layout", %{"id" => "orders", "label" => "Orders today"})
      assert has_element?(view, "#workspace-layout-orders", "Orders today")

      view |> element("#workspace-layout-clear-default-orders") |> render_click()
      assert SavedLayouts.default_slug(@settings_scope) == nil

      view |> element("#workspace-layout-delete-people") |> render_click()
      assert_modal_dialog(view, "workspace-delete-layout", "The layout “People” will be deleted.")
      view |> element("#workspace-delete-layout-cancel") |> render_click()
      refute has_element?(view, "#workspace-delete-layout")
      assert {:ok, _} = SavedLayouts.fetch(@settings_scope, "people")

      view |> element("#workspace-layout-delete-people") |> render_click()
      view |> element("#workspace-delete-layout-confirm") |> render_click()
      refute has_element?(view, "#workspace-layout-people")
      assert SavedLayouts.fetch(@settings_scope, "people") == :error

      # Deleting the layout on screen keeps the tiles and drops the address.
      view |> element("#workspace-layout-delete-orders") |> render_click()
      view |> element("#workspace-delete-layout-confirm") |> render_click()
      assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%29")
      assert has_element?(view, "#tile-t1-page")
    end
  end

  test "shared workspace opens for company viewer while a forbidden tile stays closed", %{
    conn: conn
  } do
    {:ok, entry} =
      SharedLayouts.publish(
        Settings.Scope.company(73),
        "Team desk",
        "h.5(/companies,/users)",
        []
      )

    {:ok, view, _html} = open(conn, "/workspace/shared/#{entry["slug"]}")
    assert has_element?(view, "#tile-t1-page[src='/companies']")
    assert has_element?(view, "#tile-t2-forbidden")
    refute has_element?(view, "#tile-t2-page")

    view |> element("#workspace-open-layouts") |> render_click()
    assert has_element?(view, "#workspace-shared-open-team-desk")
    view |> element("#workspace-shared-copy-team-desk") |> render_click()
    assert_patch(view, "/workspace/team-desk")
    assert {:ok, _} = SavedLayouts.fetch(@settings_scope, "team-desk")

    CompanyFixtures.insert_tenant!(%{id: 52, is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 84, tenant_id: 52, code: "other-company"})

    UserFixtures.insert_user!(%{
      id: 96,
      company_id: 84,
      name: "Other user",
      email: "other@example.com"
    })

    assert {:error, {:live_redirect, %{to: "/workspace"}}} =
             conn
             |> log_in_as(session_user(%{"user_id" => 96, "company_id" => 84}))
             |> live("/workspace/shared/team-desk")
  end

  test "copying the open shared workspace keeps the viewer's arrangement", %{conn: conn} do
    {:ok, _} = SharedLayouts.publish(Settings.Scope.company(73), "Team desk", "/companies", [])

    {:ok, view, _html} =
      open(conn, "/workspace/shared/team-desk?t=h.5(%2Fcompanies,%2Fcompanies)")

    view |> element("#workspace-open-layouts") |> render_click()
    view |> element("#workspace-shared-copy-team-desk") |> render_click()
    assert_patch(view, "/workspace/team-desk")

    assert {:ok, %{"tree" => "h.5(/companies,/companies)"}} =
             SavedLayouts.fetch(@settings_scope, "team-desk")
  end

  test "an account without a company is refused at sign-in before any workspace route mounts",
       %{conn: conn} do
    UserFixtures.insert_user!(%{
      id: 96,
      company_id: nil,
      name: "Loner",
      email: "loner@example.com"
    })

    grant_capabilities!("ui.workspace.publish", user_id: 96)
    {:ok, _} = SharedLayouts.publish(Settings.Scope.company(73), "Team desk", "/companies", [])
    conn = log_in_as(conn, session_user(%{"user_id" => 96, "company_id" => nil}))

    for path <- ["/workspace", "/workspace/shared/team-desk", "/workspace/shared-layouts"] do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
    end
  end

  test "a shared workspace does not replace the empty workspace", %{conn: conn} do
    {:ok, _} = SharedLayouts.publish(Settings.Scope.company(73), "Team desk", "/companies", [])

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#workspace-empty-state", "No pages open")

    view |> element("#workspace-open-layouts") |> render_click()
    assert has_element?(view, "#workspace-shared-open-team-desk")
  end

  test "a role-limited workspace is visible only to assigned people in its company", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, role} = Authz.create_role(scope, 73, %{name: "Reviewer", code: "reviewer"})
    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    {:ok, _} =
      SharedLayouts.publish(Settings.Scope.company(73), "Review", "/companies", ["reviewer"])

    {:ok, owner, _html} = conn |> log_in_as() |> live("/workspace?t=/companies")
    owner |> element("#workspace-open-layouts") |> render_click()
    assert has_element?(owner, "#workspace-shared-review")

    UserFixtures.insert_user!(%{id: 96, company_id: 73, name: "Peer", email: "peer@example.com"})

    {:ok, peer, _html} =
      conn
      |> log_in_as(session_user(%{"user_id" => 96, "company_id" => 73}))
      |> live("/workspace?t=/companies")

    peer |> element("#workspace-open-layouts") |> render_click()
    refute has_element?(peer, "#workspace-shared-review")
  end

  test "publishing and the shared workspace list require the publish capability", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/workspace/shared-layouts")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live("/workspace/shared-layouts")

    grant_capabilities!("ui.workspace.publish")
    {:ok, index, _html} = conn |> log_in_as() |> live("/workspace/shared-layouts")
    assert has_element?(index, "#shared-workspace-start")

    {:ok, view, _html} = conn |> log_in_as() |> live("/workspace/shared-layouts?t=%2Fcompanies")

    view
    |> form("#shared-workspace-form", %{
      "layout" => %{"label" => "Control desk"}
    })
    |> render_submit()

    assert has_element?(view, "#shared-workspace-control-desk", "Control desk")
    assert [%{"slug" => "control-desk"}] = SharedLayouts.list(Settings.Scope.company(73))

    view |> element("#shared-workspace-delete-control-desk") |> render_click()
    assert_modal_dialog(view, "shared-workspace-delete-confirmation", "will be deleted")
    view |> element("#shared-workspace-delete-confirmation-cancel") |> render_click()
    assert [%{"slug" => "control-desk"}] = SharedLayouts.list(Settings.Scope.company(73))
  end
end
