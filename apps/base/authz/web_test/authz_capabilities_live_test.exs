defmodule BilimbiWeb.AuthzCapabilitiesLiveTest do
  @moduledoc """
  Registered capabilities catalog page.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  defp open(conn) do
    grant_capabilities!("admin.authz.capability.list")
    conn |> log_in_as() |> live(~p"/authz/capabilities")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/authz/capabilities")
  end

  test "redirects away without admin.authz.capability.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/authz/capabilities")
  end

  test "lists registered capabilities with module names and marks nav row active", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#capabilities-index")
    assert has_element?(view, "#capabilities-table", "admin.authz.capability.list")
    assert has_element?(view, "#capabilities-table", "Base / Authz")
    assert has_element?(view, "#nav-admin-authz-capability[aria-current='page']")
  end

  test "shows pagination summary without dead controls on single page", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#capabilities-filters", %{"search" => "decision-log"}) |> render_change()

    assert has_element?(view, "#capabilities-pagination-summary")
    refute has_element?(view, "#capabilities-prev")
    refute has_element?(view, "#capabilities-next")
  end

  test "filters capabilities by search query", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#capabilities-filters", %{"search" => "decision-log"}) |> render_change()

    assert has_element?(view, "#capabilities-table", "admin.authz.decision-log.list")
    refute has_element?(view, "#capabilities-table", "admin.authz.role.list")
  end

  test "filters capabilities by module name search", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#capabilities-filters", %{"search" => "Core / User"}) |> render_change()

    assert has_element?(view, "#capabilities-table", "admin.user.create")
    assert has_element?(view, "#capabilities-table", "Core / User")
    refute has_element?(view, "#capabilities-table", "admin.authz.role.list")
  end

  test "filters capabilities by domain dropdown", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#capabilities-filters", %{"domain" => "admin"}) |> render_change()

    assert has_element?(view, "#capabilities-table", "admin.authz.capability.list")
  end

  test "renders empty state when no capabilities match search", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view
    |> form("#capabilities-filters", %{"search" => "xyz_nonexistent_token_123"})
    |> render_change()

    assert has_element?(view, "#capabilities-table-empty", "No capabilities match these filters.")
  end

  test "sorts table by clicking column headers", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # Sort by module
    view |> element("#capabilities-sort-module") |> render_click()

    assert_patched(
      view,
      ~p"/authz/capabilities?domain=&page=1&per_page=25&search=&sort_by=module&sort_dir=asc"
    )

    # Invert to desc
    view |> element("#capabilities-sort-module") |> render_click()

    assert_patched(
      view,
      ~p"/authz/capabilities?domain=&page=1&per_page=25&search=&sort_by=module&sort_dir=desc"
    )
  end
end
