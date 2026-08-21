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

    view |> form("#menu-inspector-filters", %{"search" => "menu-inspector"}) |> render_change()

    assert has_element?(view, "#menu-inspector", "admin.system.menu-inspector")
    refute has_element?(view, "#menu-inspector", "admin.system.info")
  end

  test "source filter narrows by contributing module", %{conn: conn} do
    grant_capabilities!("admin.system.menu-inspector.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/menu-inspector")

    view |> form("#menu-inspector-filters", %{"source" => "base/authz"}) |> render_change()

    assert has_element?(view, "#menu-inspector", "admin.authz")
    refute has_element?(view, "#menu-inspector", "admin.system.info")
  end
end
