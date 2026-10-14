defmodule Bilimbi.Core.AgentAccess.Web.AuthorizeLive do
  @moduledoc """
  Browser consent for registered MCP clients. The current person's sealed scope
  owns the grant. Opening the URL does nothing; only a CSRF-protected human
  submit issues a code. Invalid callbacks render an error and never redirect.
  """
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.AgentAccess
  # Self-service consent derives its owner from the sealed scope, with no admin grant.
  @write_guard_opt_out ~w(approve deny dismiss)

  def mount(_, _, socket),
    do: {:ok, assign(socket, request: nil, error: nil, expires_at: nil)}

  def handle_params(params, _uri, socket) do
    # The host supplies this endpoint on the socket. Never use the request's
    # Host header as an OAuth issuer or resource and never depend on Web by name.
    endpoint = socket.endpoint
    resource = endpoint.url() <> "/mcp"

    with %{type: :user, impersonator_id: nil, facet: nil} <-
           Scope.actor(socket.assigns.current_scope.scope),
         {:ok, request} <- AgentAccess.authorization_request(params, resource) do
      {:noreply,
       assign(socket,
         request: request,
         expires_at: AgentAccess.connection_expiry(),
         resource: resource,
         issuer: String.replace_suffix(resource, "/mcp", ""),
         error: nil
       )}
    else
      {:error, reason} ->
        {:noreply, assign(socket, request: nil, error: message(reason))}

      _ ->
        {:noreply, assign(socket, request: nil, error: message(:person_required))}
    end
  end

  def handle_event("approve", params, socket) when map_size(params) > 0,
    do: {:noreply, assign(socket, error: message(:invalid_expiry))}

  def handle_event("approve", _, socket) do
    if socket.assigns.request do
      case AgentAccess.authorize(
             socket.assigns.current_scope.scope,
             socket.assigns.request,
             socket.assigns.resource,
             socket.assigns.expires_at
           ) do
        {:ok, code} -> {:noreply, return_to_client(socket, %{code: code})}
        {:error, reason} -> {:noreply, assign(socket, error: message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("deny", _, socket) do
    if socket.assigns.request do
      # Revalidate the operator's callback allowlist on refusal, too.
      case AgentAccess.authorization_request(socket.assigns.request, socket.assigns.resource) do
        {:ok, _} -> {:noreply, return_to_client(socket, %{error: "access_denied"})}
        {:error, reason} -> {:noreply, assign(socket, request: nil, error: message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss", _, socket), do: {:noreply, assign(socket, error: nil)}

  defp return_to_client(socket, result) do
    request = socket.assigns.request
    uri = URI.parse(request["redirect_uri"])

    query =
      URI.decode_query(uri.query || "")
      |> Map.merge(Map.new(result, fn {k, v} -> {Atom.to_string(k), v} end))
      |> Map.merge(%{"state" => request["state"], "iss" => socket.assigns.issuer})

    redirect(socket, external: URI.to_string(%{uri | query: URI.encode_query(query)}))
  end

  defp message(:person_required),
    do: "Connect from your own account. Impersonation and agents cannot approve connections."

  defp message(:invalid_expiry),
    do: "The connection end time cannot be changed here. Start a new connection."

  defp message(:invalid_client),
    do:
      "This client is not registered. Ask the platform operator to register its OAuth client and callback address."

  defp message(_),
    do: "This connection request is invalid. Return to your client and start a new connection."

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={nil}>
      <.page variant={:form}>
        <.header>Connect an app</.header>
        <.panel_notice
          :if={@error && @request}
          id="oauth-consent-error"
          kind={:error}
          on_dismiss={JS.push("dismiss")}
        >
          {@error}
        </.panel_notice>
        <.empty_state
          :if={!@request}
          id="oauth-consent-error"
          title="Connection unavailable"
          reason={@error}
        />
        <.card :if={@request} id="oauth-consent">
          <.section_heading title="Review connection" />
          <.list id="oauth-client-details">
            <:item title="App">{@request["client_name"]}</:item>
            <:item title="Returns to">{@request["redirect_uri"]}</:item>
          </.list>
          <p class="text-sm text-muted">
            This app acts as you in your current company. It can read records and request supported changes within your permissions. Review and approve each write in the app before it commits. You can revoke this connection in Your connections.
          </p>
          <p id="oauth-connection-end" class="text-sm text-muted">
            Connection ends <.datetime id="oauth-expiry" value={@expires_at} />.
          </p>
          <.form for={%{}} id="oauth-consent-form" phx-submit="approve">
            <.button id="oauth-consent-approve" type="submit" phx-disable-with="Connecting…">Approve connection</.button>
            <.button id="oauth-consent-deny" type="button" phx-click="deny">Refuse</.button>
          </.form>
        </.card>
        <.link navigate={~p"/settings/agent-connections"}>Your connections</.link>
      </.page>
    </Layouts.app>
    """
  end
end
