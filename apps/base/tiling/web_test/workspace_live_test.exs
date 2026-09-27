defmodule Bilimbi.Base.Tiling.WorkspaceLiveTest do
  @moduledoc """
  The tiled workspace through the real host: the picker, the tree in the
  URL, every tile operation the hook and the tile menu push, the permission
  refusal in place of a frame, the chromeless refusal to nest, and saved
  layouts.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tiling.SavedLayouts
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
             "#tile-t1[data-focused='true'] iframe#tile-t1-page[src='/companies']"
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

  test "the tree in the URL reproduces the screen, and a bad one opens empty", %{conn: conn} do
    {:ok, view, _html} = open(conn, "/workspace?t=v.6(/companies,/companies)")

    assert has_element?(view, "#tile-t1[style*='height: 60.0%']")
    assert has_element?(view, "#tile-t2[style*='top: 60.0%']")
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
          "%2F%5Cevil.example%2Flogin"
        ] do
      {:ok, view, html} = open(conn, "/workspace?t=" <> tree)

      assert html =~ "could not be read"
      assert has_element?(view, "#workspace-empty-state")
      refute has_element?(view, "[data-tile]")
    end

    {:ok, view, _html} = open(conn, "/workspace?t=/companies")
    render_hook(view, "tile-navigated", %{"id" => "t1", "path" => "//evil.example/login"})
    assert has_element?(view, "#tile-t1-page[src='/companies']")
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
    assert has_element?(view, "#tile-t2[style*='left: 0.0%']")

    view |> element("#tile-t2-header-split") |> render_click()
    assert_patch(view, "/workspace?t=v.5%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#split-s3[aria-orientation='horizontal']")

    render_hook(view, "resize-split", %{"id" => "s3", "ratio" => 0.3})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#split-s3[style*='top: 30.0%']")

    render_hook(view, "nudge-split", %{"id" => "s3", "side" => "down"})
    assert_patch(view, "/workspace?t=v.35%28%2Fcompanies%2C%2Fcompanies%29")

    render_hook(view, "resize-step", %{"side" => "up"})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")

    render_hook(view, "move-tile", %{"id" => "t2", "side" => "down"})
    assert_patch(view, "/workspace?t=v.3%28%2Fcompanies%2C%2Fcompanies%29")
    assert has_element?(view, "#tile-t1[style*='top: 0.0%']")

    view |> element("#tile-t2-header-monocle") |> render_click()
    assert has_element?(view, "#workspace[data-monocle='true']")
    assert has_element?(view, "#tile-t2[style*='width: 100%']")
    assert has_element?(view, "#tile-t1[hidden]")
    refute has_element?(view, "#split-s3")
    assert has_element?(view, "#tile-t2-header-monocle", "Show every tile")

    view |> element("#tile-t2-header-close") |> render_click()
    assert_patch(view, "/workspace?t=%2Fcompanies")
    refute has_element?(view, "#tile-t2")
    assert has_element?(view, "#tile-t1[data-focused='true']")
    assert has_element?(view, "#workspace[data-monocle='false']")
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

  test "the workspace holds six tiles at most", %{conn: conn} do
    six =
      "h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,h.5(/companies,/companies)))))"

    {:ok, view, _html} = open(conn, "/workspace?t=#{six}")

    assert has_element?(view, "#workspace[data-tile-count='6']")

    view |> element("#workspace-add-page") |> render_click()
    refute has_element?(view, "#workspace-picker")
    assert render(view) =~ "holds 6 tiles at most"

    render_hook(view, "add-tile", %{"path" => "/companies"})
    refute has_element?(view, "#tile-t7")
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
      assert has_element?(view, "#tile-t1-page[src='/companies']")

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
end
