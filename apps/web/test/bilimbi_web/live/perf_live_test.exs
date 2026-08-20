defmodule BilimbiWeb.PerfLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Perf.Reporter
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias BilimbiWeb.PerfTelemetry

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.assign_primary_company!(41, 73)
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/performance")
  end

  test "redirects an actor without admin.system.perf.view", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/performance")
  end

  test "shows only redacted history and preserves bounded filters in the URL", %{conn: conn} do
    grant_capabilities!("admin.system.perf.view")
    record_request("/reports/:id")

    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live(~p"/system/performance?kind=request&identity=/reports/:id&page_size=25")

    assert has_element?(view, "#nav-admin-system-performance[aria-current='page']")
    assert has_element?(view, "#performance-sample-table td", "/reports/:id")
    assert has_element?(view, "#performance-recorder", "Available")
    assert has_element?(view, "#performance-pending", "0")
    assert has_element?(view, "#performance-dropped", "0")
    assert has_element?(view, "#performance-regression-table")
    refute render(view) =~ "credential"

    view
    |> form("#performance-filters", %{
      "filters" => %{
        "kind" => "job",
        "identity" => "base/report-export",
        "outcome" => "error",
        "page_size" => "50"
      }
    })
    |> render_change()

    assert_patch(
      view,
      "/system/performance?identity=base%2Freport-export&kind=job&outcome=error&page=1&page_size=50"
    )
  end

  test "dashboard widget is capability gated and links to diagnostics", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")
    refute has_element?(view, "#stat-performance")

    grant_capabilities!("admin.system.perf.view")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    assert has_element?(view, "#stat-performance[href='/system/performance']", "Available")
  end

  test "real LiveView telemetry records successive interactions without leaking state", %{
    conn: conn
  } do
    :ok = PerfTelemetry.attach_handlers()
    on_exit(&PerfTelemetry.detach_handlers/0)
    grant_capabilities!("admin.system.perf.view")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/performance")

    view
    |> form("#performance-filters", %{
      "filters" => %{"kind" => "request", "identity" => "", "outcome" => ""}
    })
    |> render_change()

    :sys.get_state(Reporter)

    assert {:ok, %{total: total}} =
             Perf.list_samples(
               identity: "liveview:Elixir.Bilimbi.Base.Perf.Web.IndexLive",
               page_size: 25
             )

    assert total >= 2

    before_restart = total

    :telemetry.execute(
      [:phoenix, :live_view, :handle_event, :start],
      %{monotonic_time: System.monotonic_time()},
      %{socket: %{view: Bilimbi.Base.Perf.Web.IndexLive}, event: "filter", params: %{}}
    )

    :ok = PerfTelemetry.attach_handlers()

    :telemetry.execute(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{socket: %{view: Bilimbi.Base.Perf.Web.IndexLive}, event: "filter", params: %{}}
    )

    :sys.get_state(Reporter)

    assert {:ok, %{total: ^before_restart}} =
             Perf.list_samples(
               identity: "liveview:Elixir.Bilimbi.Base.Perf.Web.IndexLive",
               page_size: 25
             )
  end

  defp record_request(route) do
    generation = make_ref()

    Perf.handle_event(
      [:phoenix, :router_dispatch, :start],
      %{monotonic_time: System.monotonic_time()},
      %{route: route, query_string: "credential=secret"},
      generation
    )

    Perf.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{conn: %{status: 200, resp_body: "safe"}},
      generation
    )

    :sys.get_state(Reporter)
  end
end
