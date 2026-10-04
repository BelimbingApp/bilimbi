defmodule Bilimbi.Core.User.Web.NotificationSubscription do
  @moduledoc """
  Keeps the shell's notification bell live on every authenticated page.

  The shared shell renders the bell from the `shell.notifications` embed
  (`priv/web_routes.exs`); this `on_mount` hook is its other half. On a
  connected mount it subscribes the LiveView to the signed-in account's
  notification topic once, and refreshes the bell whenever an event arrives.
  The host attaches it to every discovered live session after the route check
  (`BilimbiWeb.DiscoveredRoutes`), so a page never subscribes for itself and
  never names the bell.

  The event stops here. A page other than `/notifications` has no clause for
  it, and a LiveView with a `handle_info/2` that lacks a catch-all would crash
  on a message it never asked for. `NotificationsLive` is the one view that
  also reloads its own list, so the event continues to it.

  A framed render (a page inside a workspace tile) has no top bar and so no
  bell: nothing is refreshed there, and only the notifications list still
  subscribes. An anonymous or public page has no scope and is left alone.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, send_update: 2]

  require Logger

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.DiscoveredPanels
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Web.NotificationBellComponent
  alias Bilimbi.Core.User.Web.NotificationsLive

  @bell_id DiscoveredPanels.shell_id("shell.notifications")

  @doc false
  def on_mount(:attach, _params, _session, socket) do
    case socket.assigns[:current_scope] do
      %{scope: %Scope{} = scope} = current_scope ->
        bell? = current_scope[:framed] != true
        list? = socket.view == NotificationsLive

        if connected?(socket) and (bell? or list?) do
          {:cont,
           subscribe(socket, scope, Bilimbi.Base.UI.current_user_id(current_scope), bell?, list?)}
        else
          {:cont, socket}
        end

      _no_scope ->
        {:cont, socket}
    end
  end

  defp subscribe(socket, scope, user_id, bell?, list?) do
    case User.subscribe_notifications(scope, user_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "failed to subscribe to the notifications topic for user #{user_id}: #{inspect(reason)}"
        )
    end

    attach_hook(socket, :user_notifications, :handle_info, fn
      {:notification_event, _event}, socket ->
        if bell?, do: send_update(NotificationBellComponent, id: @bell_id)
        if list?, do: {:cont, socket}, else: {:halt, socket}

      _other, socket ->
        {:cont, socket}
    end)
  end
end
