defmodule BilimbiWeb.ActionFailureRecoveryLiveTest do
  use BilimbiWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz.AuthorizationDeniedError
  alias Bilimbi.Base.Authz.Decision

  defmodule RecoveryComponent do
    use Bilimbi.Base.UI, :live_component

    @impl true
    def render(assigns) do
      ~H"""
      <button id="raise-component" phx-click="raise-component" phx-target={@myself}>
        Raise in component
      </button>
      """
    end

    @impl true
    def handle_event("raise-component", _params, _socket) do
      raise "unexpected component action failure"
    end
  end

  defmodule RecoveryLive do
    use BilimbiWeb, :live_view

    @impl true
    def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

    @impl true
    def render(assigns) do
      ~H"""
      <div id="action-recovery-probe">
        <button id="raise-view" phx-click="raise-view">Raise in view</button>
        <button id="increment" phx-click="increment">Increment</button>
        <span id="count">{@count}</span>
        <p id="action-error">{Phoenix.Flash.get(@flash, :error)}</p>
        <.live_component module={RecoveryComponent} id="recovery-component" />
      </div>
      """
    end

    @impl true
    def handle_event("raise-view", _params, _socket) do
      raise "unexpected view action failure"
    end

    def handle_event("deny", _params, _socket) do
      raise AuthorizationDeniedError,
        decision: Decision.deny(:denied_missing_capability)
    end

    def handle_event("missing", _params, _socket) do
      raise %Ecto.NoResultsError{message: "expected record was not found"}
    end

    def handle_event("invalid-changeset", _params, _socket) do
      raise %Ecto.InvalidChangesetError{
        action: :insert,
        changeset: %Ecto.Changeset{valid?: false}
      }
    end

    def handle_event("increment", _params, socket) do
      {:noreply, update(socket, :count, &(&1 + 1))}
    end
  end

  test "an unexpected LiveView exception is logged and the same mount remains usable", %{
    conn: conn
  } do
    {:ok, view, _html} = live_isolated(conn, RecoveryLive)
    pid = view.pid

    log =
      capture_log(fn ->
        view |> element("#raise-view") |> render_click()
      end)

    assert log =~ "** (RuntimeError) unexpected view action failure"
    assert view.pid == pid
    assert Process.alive?(pid)

    assert has_element?(
             view,
             "#action-error",
             "That action did not finish. The error has been recorded — if it keeps happening, tell your administrator."
           )

    view |> element("#increment") |> render_click()
    assert has_element?(view, "#count", "1")
  end

  test "the same recovery boundary covers LiveComponent actions", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, RecoveryLive)
    pid = view.pid

    log =
      capture_log(fn ->
        view |> element("#raise-component") |> render_click()
      end)

    assert log =~ "** (RuntimeError) unexpected component action failure"
    assert view.pid == pid
    assert Process.alive?(pid)

    _ = :sys.get_state(pid)

    assert has_element?(
             view,
             "#action-error",
             "That action did not finish. The error has been recorded — if it keeps happening, tell your administrator."
           )
  end

  test "authorization denial still propagates" do
    assert_raise AuthorizationDeniedError, fn ->
      RecoveryLive.handle_event("deny", %{}, %Phoenix.LiveView.Socket{})
    end
  end

  test "expected Ecto outcomes still propagate" do
    assert_raise Ecto.NoResultsError, fn ->
      RecoveryLive.handle_event("missing", %{}, %Phoenix.LiveView.Socket{})
    end

    assert_raise Ecto.InvalidChangesetError, fn ->
      RecoveryLive.handle_event("invalid-changeset", %{}, %Phoenix.LiveView.Socket{})
    end
  end
end
