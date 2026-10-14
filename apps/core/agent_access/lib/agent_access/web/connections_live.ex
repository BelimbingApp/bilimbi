defmodule Bilimbi.Core.AgentAccess.Web.ConnectionsLive do
  @moduledoc "The person's own grants and observed identity changes; no token values leave the facade."
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Core.AgentAccess
  # Self-service: only the sealed owner can list or revoke their grants.
  @write_guard_opt_out ~w(revoke confirm_revoke cancel_revoke)
  def mount(_, _, socket), do: {:ok, socket |> assign(pending: nil) |> load()}

  defp load(socket) do
    case AgentAccess.list_connections(socket.assigns.current_scope.scope) do
      {:ok, rows} ->
        socket
        |> assign(error: nil, count: length(rows))
        |> stream(:connections, rows, reset: true)

      {:error, _} ->
        socket
        |> assign(error: "Use your own account to manage connections.", count: 0)
        |> stream(:connections, [], reset: true)
    end
  end

  def handle_event("revoke", %{"id" => id}, socket), do: {:noreply, assign(socket, pending: id)}
  def handle_event("cancel_revoke", _, socket), do: {:noreply, assign(socket, pending: nil)}

  def handle_event("confirm_revoke", _, socket) do
    result =
      AgentAccess.revoke(
        socket.assigns.current_scope.scope,
        Bilimbi.Base.UI.Params.positive_integer(socket.assigns.pending)
      )

    socket = socket |> assign(pending: nil) |> load()

    {:noreply,
     if(result == :ok,
       do: put_flash(socket, :success, "Connection revoked."),
       else: put_flash(socket, :error, "Connection was not revoked. It may already be revoked.")
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={nil}>
      <.page variant={:list}>
        <.header>Agent connections</.header>
        <.empty_state
          :if={@error}
          id="connections-error"
          title="Connections unavailable"
          reason={@error}
        />
        <.empty_state
          :if={@count == 0 and is_nil(@error)}
          id="connections-empty"
          title="No connections"
          reason="Connect an app or agent through its sign-in flow."
        />
        <div id="agent-connections" phx-update="stream">
          <.card :for={{dom_id, connection} <- @streams.connections} id={dom_id} class="mb-2">
            <.section_heading title={connection.agent_id} />
            <.list>
              <:item title="Ends">
                <.datetime id={"connection-expiry-#{connection.id}"} value={connection.expires_at} />
              </:item>
              <:item title="Status">
                {if connection.revoked_at,
                  do: "Revoked",
                  else:
                    if(DateTime.compare(connection.expires_at, DateTime.utc_now()) == :gt,
                      do: "Connected",
                      else: "Expired"
                    )}
              </:item>
              <:item :if={map_size(connection.seen_agent_ids) > 0} title="Also seen as">
                <span class="text-warning-ink">{connection.seen_agent_ids
                |> Map.keys()
                |> Enum.sort()
                |> Enum.join(", ")}</span>
              </:item>
            </.list>
            <.button
              :if={is_nil(connection.revoked_at)}
              id={"revoke-#{connection.id}"}
              phx-click="revoke"
              phx-value-id={connection.id}
            >Revoke</.button>
          </.card>
        </div>
        <.confirm_dialog
          :if={@pending}
          id="revoke-connection-dialog"
          consequence="Revoke connection?"
          detail="Access ends immediately. Connect again and approve a new connection to grant access again."
          on_confirm={JS.push("confirm_revoke")}
          on_cancel={JS.push("cancel_revoke")}
          confirm="Revoke"
          working="Revoking…"
        />
      </.page>
    </Layouts.app>
    """
  end
end
