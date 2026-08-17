defmodule BilimbiWeb.UIReferenceLiveTest do
  @moduledoc """
  End-to-end tests for the canonical UI Reference page at `/system/ui-reference`.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @view_cap "admin.system.ui-reference.view"

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn) do
    grant_capabilities!(@view_cap)
    conn |> log_in_as() |> live(~p"/system/ui-reference")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/ui-reference")
  end

  test "redirects away when the actor lacks admin.system.ui-reference.view", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/ui-reference")
  end

  test "renders the UI reference page and design tokens when authorized", %{conn: conn} do
    {:ok, view, html} = open(conn)

    assert html =~ "UI Component Reference"
    assert html =~ "resources/core/views/components/ui/button.blade.php"
    assert html =~ "resources/core/views/components/ui/table.blade.php"
    assert html =~ "resources/core/css/tokens.css"

    # Verifies key showcase components are rendered
    assert has_element?(view, "#component-header")
    assert has_element?(view, "#component-button")
    assert has_element?(view, "#component-badge")
    assert has_element?(view, "#component-alert")
    assert has_element?(view, "#component-table")
    assert has_element?(view, "#component-inputs")
    assert has_element?(view, "#component-datetime")
    assert has_element?(view, "#component-icons")

    # Verifies sample table content
    assert has_element?(view, "#sample-table", "Acme Holdings")
    assert has_element?(view, "#sample-table", "Globex Corporation")

    # Verifies sidebar active nav
    assert has_element?(view, "#nav-admin-system-ui-reference[aria-current='page']")
  end

  test "handles interactive button clicks", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "button", "Clicked: 0")

    view
    |> element("button", "Clicked: 0")
    |> render_click()

    assert has_element?(view, "button", "Clicked: 1")
  end
end
