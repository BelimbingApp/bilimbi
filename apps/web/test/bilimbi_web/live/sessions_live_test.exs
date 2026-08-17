defmodule BilimbiWeb.SessionsLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Session
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
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/sessions")
  end

  test "redirects away when the actor lacks admin.system.session.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/sessions")
  end

  test "lists sessions without joining Core User", %{conn: conn} do
    grant_capabilities!("admin.system.session.list")

    {:ok, _} =
      Session.put_session("guest-row", "{}", %{
        ip_address: "10.0.0.9",
        user_agent: "GuestAgent/1.0",
        last_activity: System.system_time(:second)
      })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/sessions")

    assert has_element?(view, "h1", "Sessions")

    # The sidebar row for this page must be marked current. A screen that
    # names no menu item still renders correctly, so nothing but an assertion
    # notices -- which is how this shipped unhighlighted in the first place.
    assert has_element?(view, "#nav-admin-system-session[aria-current='page']")
    assert has_element?(view, "#sessions")
    assert has_element?(view, "#sessions-search")
    assert has_element?(view, "#sessions td", "User 91")
    assert has_element?(view, "#sessions td", "Guest")
    assert has_element?(view, "#sessions td", "10.0.0.9")
    refute has_element?(view, "#sessions-terminate-guest-row")

    view |> form("#sessions-search", %{q: "no-such-agent-xyz"}) |> render_change()
    assert has_element?(view, "#sessions-empty", "No sessions found.")
  end

  test "terminates a non-current session when the actor can manage sessions", %{conn: conn} do
    grant_capabilities!(["admin.system.session.list", "admin.system.session.manage"])

    {:ok, _} =
      Session.put_session("other-session", "{}", %{
        user_id: 91,
        ip_address: "192.0.2.10",
        user_agent: "OtherAgent/1.0",
        last_activity: System.system_time(:second)
      })

    conn = log_in_as(conn)
    current_id = Plug.Conn.get_session(conn, "current_user")["session_id"]

    {:ok, view, _html} = live(conn, ~p"/system/sessions")

    assert has_element?(view, "#sessions-terminate-other-session")
    refute has_element?(view, "#sessions-terminate-#{current_id}")

    render_click(view, "terminate", %{"id" => current_id})
    assert has_element?(view, "#flash-error", "You cannot terminate your current session.")

    view |> element("#sessions-terminate-other-session") |> render_click()

    assert has_element?(view, "#flash-info", "Session terminated.")
    refute has_element?(view, "#sessions-terminate-other-session")
    assert {:error, :not_found} = Session.fetch_session("other-session")
    assert {:ok, _} = Session.fetch_session(current_id)
  end

  test "refuses terminate without admin.system.session.manage", %{conn: conn} do
    grant_capabilities!("admin.system.session.list")

    {:ok, _} =
      Session.put_session("protected-session", "{}", %{
        user_id: 91,
        last_activity: System.system_time(:second)
      })

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/sessions")

    render_click(view, "terminate", %{"id" => "protected-session"})

    assert has_element?(view, "#flash-error", "You do not have permission to terminate sessions.")
    assert {:ok, _} = Session.fetch_session("protected-session")
  end
end
