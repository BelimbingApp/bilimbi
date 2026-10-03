defmodule Bilimbi.Base.UI.EventAuthorizationTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.EventAuthorization

  defmodule Component do
    use Bilimbi.Base.UI, :live_component

    def handle_event("write", _params, socket) do
      send(self(), {:written, socket.assigns.current_scope})
      {:noreply, socket}
    end
  end

  test "component dispatch uses refreshed authority before invoking its handler" do
    EventAuthorization.install(fn socket ->
      {:cont, Phoenix.Component.assign(socket, :current_scope, :refreshed)}
    end)

    assert {:noreply, _} = Component.handle_event("write", %{}, socket())
    assert_received {:written, :refreshed}
  end

  test "refused component dispatch never invokes its handler" do
    EventAuthorization.install(fn socket -> {:halt, socket} end)

    assert {:noreply, _} = Component.handle_event("write", %{}, socket())
    refute_received {:written, _}
  end

  test "replacing the owning page policy affects the next component event" do
    EventAuthorization.install(fn socket -> {:cont, socket} end)
    assert {:noreply, _} = Component.handle_event("write", %{}, socket())
    assert_received {:written, :stale}

    EventAuthorization.install(fn socket -> {:halt, socket} end)
    assert {:noreply, _} = Component.handle_event("write", %{}, socket())
    refute_received {:written, _}
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_scope: :stale},
      private: %{live_temp: %{}}
    }
  end
end
