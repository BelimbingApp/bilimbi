defmodule BilimbiWeb.SystemInfoLiveTest do
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
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/info")
  end

  # Belimbing declares `admin.system.info.view` on the menu item
  # (`app/Base/System/Config/menu.php:7`) but omits `authz:` from the route
  # (`app/Base/System/Routes/web.php:16`), so the screen is reachable there by
  # any authenticated user. Menu-level hiding is not access control; this
  # screen enforces the capability Belimbing already declares for it.
  test "redirects away without admin.system.info.view", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/info")
  end

  test "renders every card with real runtime facts", %{conn: conn} do
    grant_capabilities!("admin.system.info.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/info")

    assert has_element?(view, "h1", "System Info")

    for card <- ~w(application runtime database server health applications) do
      assert has_element?(view, "#system-info-#{card}"), "missing the #{card} card"
    end

    # Derived from the running VM, so this cannot pass against a stubbed value
    # and will not break on an Elixir upgrade.
    assert has_element?(view, "#system-info-runtime-elixir", System.version())
    assert has_element?(view, "#system-info-runtime-otp-release", System.otp_release())

    # The database row is a live probe, not config being present.
    assert has_element?(view, "#system-info-database-connection", "Connected")
  end

  test "reports the queue as unavailable rather than inventing a status", %{conn: conn} do
    grant_capabilities!("admin.system.info.view")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/info")

    # #131 (Base Queue on Oban) is unstarted. A green tick here would be the one
    # genuinely dangerous thing this screen could render.
    assert has_element?(view, "#system-info-health-queue", "Unavailable")

    # The sibling rows must NOT read Unavailable, or "everything is unavailable"
    # would satisfy the assertion above.
    refute has_element?(view, "#system-info-health-database", "Unavailable")
  end
end
