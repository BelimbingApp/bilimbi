defmodule BilimbiWeb.HostAuthorityTest do
  @moduledoc """
  An open LiveView keeps no authority its session or grants no longer give
  it. The platform security review showed pages writing after their session
  was terminated or logged out elsewhere, after their login was removed, and
  after the grant behind a mount-time assign or a route was revoked, because
  the host proved everything once at mount. `BilimbiWeb.RouteAccess` now
  re-proves the session and the route before every event and navigation,
  and `BilimbiWeb.SessionDisconnect` ends the sockets of a terminated session.
  These drive real pages
  through the discovered host routes.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias BilimbiWeb.RouteAccess
  alias BilimbiWeb.UserAuth

  @session_id "host-authority-session"
  @employee_caps ["admin.employee.list", "admin.employee.view", "admin.employee.update"]

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Audit actor"})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-1", full_name: "Grace Hopper"})

    conn = log_in_as(conn, session_user(%{"session_id" => @session_id}))
    %{scope: scope, conn: conn, employee: employee}
  end

  defp revoke!(scope, key) do
    {:ok, :stored} = Authz.put_principal_capability(scope, 73, :user, 91, key, false)
  end

  defp open_employee(c) do
    grant_capabilities!(@employee_caps)
    {:ok, view, _html} = live(c.conn, ~p"/employees/#{c.employee.id}")
    view
  end

  # The page is sent to the login screen as an expired session, and the
  # employee it showed is as it was.
  defp assert_ended(view, c) do
    assert {:error, {:redirect, %{to: "/"}}} =
             render_submit(view, "save_field", %{"full_name" => "After the end"})

    assert assert_redirect(view, "/")["session_expired"] == "expired"
    assert {:ok, %{full_name: "Grace Hopper"}} = Employee.get_employee(c.scope, 73, c.employee.id)
  end

  test "H3 a session terminated by an operator ends the open page and disconnects its sockets",
       c do
    view = open_employee(c)
    :ok = Phoenix.PubSub.subscribe(BilimbiWeb.PubSub, UserAuth.live_socket_id(@session_id))

    assert {:ok, :terminated} = Session.terminate_session(@session_id, "operator-session")

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    assert redirected_to(get(c.conn, ~p"/employees/#{c.employee.id}")) == ~p"/"
    assert_ended(view, c)
  end

  test "H4 logging out in another tab ends the open page and disconnects its sockets", c do
    view = open_employee(c)
    :ok = Phoenix.PubSub.subscribe(BilimbiWeb.PubSub, UserAuth.live_socket_id(@session_id))

    assert redirected_to(delete(c.conn, ~p"/session")) == ~p"/"
    assert {:error, :not_found} = Session.fetch_session(@session_id)

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    assert_ended(view, c)
  end

  test "a login removed while its page is open ends the page at its next action", c do
    view = open_employee(c)

    assert :ok = User.delete_user(c.scope, 73, 91)

    assert_ended(view, c)
  end

  test "H6 a same-route patch after the route grant is revoked is refused before it reads", c do
    grant_capabilities!(["admin.geonames.list"])
    CompanyFixtures.insert_country!(%{iso: "MY"})
    {:ok, view, _html} = live(c.conn, ~p"/geonames/countries")

    revoke!(c.scope, "admin.geonames.list")
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(c.conn, ~p"/geonames/countries")

    CompanyFixtures.insert_country!(%{iso: "ZZ", country: "Fresh private fact"})

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             render_hook(view, "filters", %{"filters" => %{"search" => "Fresh"}})

    assert assert_redirect(view, "/dashboard")["error"] == RouteAccess.revoked_message()
  end

  test "an event reads the refreshed capability list, not the mount's", c do
    view = open_employee(c)

    revoke!(c.scope, "admin.employee.update")

    html = render_submit(view, "save_field", %{"full_name" => "After revocation"})
    assert html =~ "permission"
    assert {:ok, %{full_name: "Grace Hopper"}} = Employee.get_employee(c.scope, 73, c.employee.id)
  end
end
