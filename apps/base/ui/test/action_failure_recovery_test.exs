defmodule Bilimbi.Base.UI.ActionFailureRecoveryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  defmodule RecoveryLive do
    use Bilimbi.Base.UI, :live_view

    def handle_event("reply", _params, socket), do: {:reply, %{accepted: true}, socket}
    def handle_event("raise", _params, _socket), do: raise("unexpected action failure")
    def handle_event("throw", _params, _socket), do: throw(:deliberate_control_flow)
  end

  test "preserves successful action results" do
    socket = socket()

    assert {:reply, %{accepted: true}, ^socket} =
             RecoveryLive.handle_event("reply", %{}, socket)
  end

  test "logs and flashes unexpected action exceptions" do
    socket = socket()

    log =
      capture_log(fn ->
        assert {:noreply, recovered_socket} =
                 RecoveryLive.handle_event("raise", %{}, socket)

        assert recovered_socket.assigns.flash["error"] ==
                 "That action did not finish. The error has been recorded — if it keeps happening, tell your administrator."
      end)

    assert log =~ "** (RuntimeError) unexpected action failure"
  end

  test "does not intercept non-exception control flow" do
    assert catch_throw(RecoveryLive.handle_event("throw", %{}, socket())) ==
             :deliberate_control_flow
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}}
    }
  end
end
