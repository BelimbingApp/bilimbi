defmodule BilimbiWeb.RouteAccess do
  @moduledoc """
  Checks the destination capability before a shared-session LiveView mounts,
  and again before every client-triggered callback while the page is open.

  Route actions carry a compile-time policy key, never a client-supplied grant.
  Clear that host-only key before calling module adapters, which historically
  receive a nil action. Authentication and operator boundaries remain UserAuth
  session hooks. A missing policy fails closed; routes sharing a LiveView
  still carry distinct policies.

  The mount gate answers from `current_scope.capabilities`, the allowed list
  stored when the scope was rehydrated. A key on that list is allowed without
  another `Bilimbi.Base.Authz.can/2`, so an allowed page view writes no
  decision-log row. A key absent from the list is still evaluated and logged.

  ## After mount

  A LiveView process outlives its mount. Its session can be terminated, its
  login removed or moved to another company, and a grant revoked, all while
  the page stays open. So before every client-triggered callback the page
  proves its authority again, in two steps:

    1. the scope is rehydrated the way an HTTP request's is
       (`BilimbiWeb.UserAuth.refresh_scope/1`: durable session row, company,
       tenant, user, effective capabilities). A miss ends the page: it is sent
       to the login screen with the expired-session flash;
    2. the route's capability (including an `{:any_of, keys}` guard) is judged
       again. An event, or a patch that stays on the same route, calls
       `Bilimbi.Base.Authz.LiveAuthorization.allowed_now?/2`: one
       `Bilimbi.Base.Authz.can/2` decision per key, so a grant removed since
       the page opened is refused and logged. Entering a different route uses
       the list just refreshed onto the scope, the same rule as the mount
       gate. A page whose capability no longer holds is sent to the dashboard
       with a flash saying why.

  Both run before every `handle_event/3`, through a `:handle_event` hook, and
  before every `handle_params/3` that live navigation triggers, whether the
  patch stays on the same route or enters another one. The first
  `handle_params` of a mount is the same callback invocation as the mount
  that just proved everything, so it is not checked twice. The refreshed
  `current_scope` is assigned, so `allowed?/2` inside the callback reads the
  current capability list rather than the mount's.

  Server-triggered callbacks (`handle_info`, `handle_async`) are not checked
  here. A LiveComponent's `handle_event/3` reaches the same authorization
  through the Base UI event wrapper and its process-local host callback.
  The callback is replaced on live navigation and refreshes the owning page's
  identity before checking its requirement. An operation needing another
  capability also uses `Bilimbi.Base.Authz.LiveAuthorization.authorize_event/2`.
  """

  use BilimbiWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3, redirect: 2]

  alias Bilimbi.Base.Authz.LiveAuthorization

  @revoked_message "Your access to that page was removed. The action was not performed."
  @expired_flash "expired"

  @doc "The flash shown when an open page's route capability no longer holds."
  @spec revoked_message() :: String.t()
  def revoked_message, do: @revoked_message

  def on_mount(policies, params, session, socket) do
    action = socket.assigns.live_action
    capability = Map.fetch!(policies, action)

    case authorize(capability, params, session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, socket} ->
        install_event_authorization(capability, socket)

        socket =
          socket
          |> put_route(action, true)
          |> assign(:live_action, nil)
          |> attach_hook(
            :route_access,
            :handle_params,
            &handle_params(policies, session, &1, &2, &3)
          )
          |> attach_hook(:route_access_event, :handle_event, &handle_event(policies, &1, &2, &3))

        {:cont, socket}
    end
  end

  defp handle_params(policies, session, params, uri, socket) do
    uri = URI.parse(uri)
    route = Phoenix.Router.route_info(socket.router, "GET", uri.path, uri.host)
    {_view, action, _opts, _session} = Map.fetch!(route, :phoenix_live_view)
    capability = Map.fetch!(policies, action)

    result =
      cond do
        # The mount that just proved this action is the same invocation.
        socket.private.bilimbi_route_checked and socket.private.bilimbi_route_action == action ->
          {:cont, socket}

        socket.private.bilimbi_route_action == action ->
          with {:cont, socket} <- refresh(socket), do: reauthorize(capability, socket)

        true ->
          with {:cont, socket} <- refresh(socket),
               do: authorize(capability, params, session, socket)
      end

    case result do
      {:cont, socket} ->
        install_event_authorization(capability, socket)
        {:cont, socket |> put_route(action, false) |> assign(:live_action, nil)}

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  defp handle_event(policies, _event, _params, socket) do
    authorize_event(Map.fetch!(policies, socket.private.bilimbi_route_action), socket)
  end

  defp authorize_event(capability, socket) do
    with {:cont, socket} <- refresh(socket), do: reauthorize(capability, socket)
  end

  defp install_event_authorization(capability, socket) do
    scope = socket.assigns[:current_scope]

    Bilimbi.Base.UI.EventAuthorization.install(fn component_socket ->
      authorize_event(capability, assign(component_socket, :current_scope, scope))
    end)
  end

  # The same four reads the HTTP plug pays per request. The frame flag is the
  # one fact a refreshed scope cannot rebuild: it came from the LiveView
  # session at mount (`BilimbiWeb.FramedRender`). A session group without a
  # scope (public routes) has nothing to refresh.
  defp refresh(%{assigns: %{current_scope: %{session_identity: _} = current_scope}} = socket) do
    case BilimbiWeb.UserAuth.refresh_scope(current_scope) do
      {:ok, refreshed} ->
        {:cont,
         assign(socket, :current_scope, Map.merge(refreshed, Map.take(current_scope, [:framed])))}

      {:error, :unauthenticated} ->
        {:halt,
         socket
         |> put_flash(:session_expired, @expired_flash)
         |> redirect(to: ~p"/")}
    end
  end

  defp refresh(socket), do: {:cont, socket}

  defp put_route(socket, action, checked?) do
    socket
    |> put_in([Access.key(:private), :bilimbi_route_action], action)
    |> put_in([Access.key(:private), :bilimbi_route_checked], checked?)
  end

  # A destination the actor has not yet proved: the mount guard's refusal.
  defp authorize(nil, _params, _session, socket), do: {:cont, socket}

  defp authorize(capability, params, session, socket) do
    BilimbiWeb.UserAuth.on_mount({:require_capability, capability}, params, session, socket)
  end

  # The action this page already proved at mount: refuse only what was
  # removed since, and say so.
  defp reauthorize(nil, socket), do: {:cont, socket}

  defp reauthorize(capability, socket) do
    if LiveAuthorization.allowed_now?(socket.assigns[:current_scope], capability) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, @revoked_message)
       |> redirect(to: ~p"/dashboard")}
    end
  end
end
