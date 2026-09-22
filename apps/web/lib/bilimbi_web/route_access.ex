defmodule BilimbiWeb.RouteAccess do
  @moduledoc """
  Checks the destination capability before a shared-session LiveView mounts.

  Route actions carry a compile-time policy key, never a client-supplied grant.
  Clear that host-only key before calling module adapters, which historically
  receive a nil action. Check patches to other routes too: a view can serve
  several routes. Query-only patches keep the existing page's mount policy.
  Authentication and operator boundaries remain UserAuth session hooks.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(policies, params, session, socket) do
    action = socket.assigns.live_action
    capability = Map.fetch!(policies, action)

    case authorize(capability, params, session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, socket} ->
        socket = put_in(socket.private[:bilimbi_route_action], action)

        socket =
          socket
          |> assign(:live_action, nil)
          |> attach_hook(:route_access, :handle_params, fn params, uri, socket ->
            uri = URI.parse(uri)
            route = Phoenix.Router.route_info(socket.router, "GET", uri.path, uri.host)
            {_view, action, _opts, _session} = Map.fetch!(route, :phoenix_live_view)
            capability = Map.fetch!(policies, action)

            result =
              if socket.private.bilimbi_route_action == action,
                do: {:cont, socket},
                else: authorize(capability, params, session, socket)

            case result do
              {:cont, socket} ->
                socket = put_in(socket.private[:bilimbi_route_action], action)
                {:cont, assign(socket, :live_action, nil)}

              {:halt, socket} ->
                {:halt, socket}
            end
          end)

        {:cont, socket}
    end
  end

  defp authorize(nil, _params, _session, socket), do: {:cont, socket}

  defp authorize(capability, params, session, socket) do
    BilimbiWeb.UserAuth.on_mount({:require_capability, capability}, params, session, socket)
  end
end
