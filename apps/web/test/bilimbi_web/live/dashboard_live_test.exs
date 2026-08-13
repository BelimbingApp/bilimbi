defmodule BilimbiWeb.DashboardLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Session
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "shows the workspace identity and real counts", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#app-tenant", "41")
    assert has_element?(view, "#stat-companies", "1")
    assert has_element?(view, "#stat-users", "1")

    assert has_element?(
             view,
             "#dashboard-current-company[data-company-id='73']"
           )

    assert has_element?(view, "#dashboard-company-name", "Bilimbi Industries")
  end

  test "lists users affiliated with the tenant's companies", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#dashboard-users")
    assert has_element?(view, "#dashboard-users td", "Ada Lovelace")
  end

  test "renders the sidebar without gated destinations when capabilities are absent", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "#nav-dashboard[aria-current='page']")
    refute has_element?(view, "#nav-companies")
    refute has_element?(view, "#nav-users")
    refute has_element?(view, "#dashboard-company-open")
    assert has_element?(view, "#app-user-name", "Ada Lovelace")
    assert has_element?(view, "#app-logout")
  end

  test "shows companies and users navigation when those capabilities are granted", %{conn: conn} do
    grant_capabilities!(["admin.company.list", "admin.company.view", "admin.user.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#nav-companies")
    assert has_element?(view, "#nav-users")
    assert has_element?(view, "#dashboard-company-open")
    assert has_element?(view, "#stat-companies[href='/companies']")
    assert has_element?(view, "#stat-users[href='/users']")
  end

  test "drops authentication when the live user is gone", %{conn: conn} do
    conn = log_in_as(conn)
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DELETE FROM users WHERE id = 91", [])

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "drops authentication when the durable session is terminated", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    :ok = Session.delete_session(session_id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end
end
