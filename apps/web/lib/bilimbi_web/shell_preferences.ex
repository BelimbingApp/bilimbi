defmodule BilimbiWeb.ShellPreferences do
  @moduledoc """
  LiveView adapter for the shell's display controls.

  Identity always comes from the live session, and the durable write and the
  resolved snapshot both belong to `Bilimbi.Core.User.DisplayPreferences`.
  """

  alias Bilimbi.Core.User.DisplayPreferences

  def attach(socket),
    do: Phoenix.LiveView.attach_hook(socket, :shell_preferences, :handle_event, &handle_event/3)

  def handle_event("shell:preference", %{"kind" => kind, "value" => value}, socket) do
    # Rehydrate the durable session before a self-service write, just as the
    # HTTP preference endpoint does. A revoked session cannot keep writing.
    with {:ok, current_scope} <- BilimbiWeb.UserAuth.refresh_scope(socket.assigns.current_scope),
         :ok <- DisplayPreferences.save(current_scope, kind, value) do
      socket =
        Phoenix.Component.assign(
          socket,
          :current_scope,
          DisplayPreferences.refresh(current_scope)
        )

      {:halt, %{ok: true}, socket}
    else
      {:error, _reason} -> {:halt, %{ok: false}, socket}
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:halt, %{ok: false}, socket}
  end

  def handle_event("shell:preference", _params, socket), do: {:halt, %{ok: false}, socket}
  def handle_event(_event, _params, socket), do: {:cont, socket}
end
