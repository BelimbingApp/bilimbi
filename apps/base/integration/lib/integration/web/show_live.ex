defmodule Bilimbi.Base.Integration.Web.ShowLive do
  @moduledoc false
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Base.{Authz, Integration}
  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.UI.Workspace

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         payload: nil,
         page_title: "API Exchange",
         active_nav: "admin.system.integration",
         confirming_delete: false
       )}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope.scope

    case Integration.get_exchange(scope, id) do
      {:ok, exchange} ->
        {:noreply,
         socket
         |> assign(:exchange, exchange)
         |> assign(
           :can_payload,
           Authz.can(scope, "admin.system.outbound-exchange.payload.view").allowed
         )
         |> assign(:can_delete, Authz.can(scope, "admin.system.outbound-exchange.delete").allowed)
         |> Workspace.announce(%{kind: "base/integration", id: id})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Exchange unavailable: #{reason}.")
         |> push_navigate(to: ~p"/system/api-exchanges")}
    end
  end

  @impl true
  def handle_event("payload", _, socket) do
    case Integration.payload(socket.assigns.current_scope.scope, socket.assigns.exchange.id) do
      {:ok, payload} -> {:noreply, assign(socket, :payload, Jason.encode!(payload, pretty: true))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Payload unavailable: #{reason}.")}
    end
  end

  def handle_event("confirm_delete", _, socket),
    do: {:noreply, assign(socket, :confirming_delete, true)}

  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, :confirming_delete, false)}

  def handle_event("delete", _, socket) do
    with {:ok, socket} <-
           LiveAuthorization.authorize_event(socket, "admin.system.outbound-exchange.delete") do
      case Integration.delete_exchange(
             socket.assigns.current_scope.scope,
             socket.assigns.exchange.id
           ) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:success, "Exchange deleted.")
           |> push_navigate(to: ~p"/system/api-exchanges")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Exchange could not be deleted: #{reason}.")}
      end
    else
      {:denied, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="exchange-detail" variant={:detail}>
        <.header>
          API Exchange<:subtitle>{@exchange.id}</:subtitle><:actions>
            <.link navigate={~p"/system/api-exchanges"}>All exchanges</.link>
          </:actions>
        </.header>
        <.card
          id="exchange-summary"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="exchange-heading"
        >
          <.section_heading id="exchange-heading" title="Exchange" />
          <.list id="exchange-facts">
            <:item title="Direction">{@exchange.direction}</:item>
            <:item title="Operation">{@exchange.operation}</:item>
            <:item title="Method">{@exchange.method || "—"}</:item>
            <:item title="Endpoint">{@exchange.endpoint}</:item>
            <:item title="Outcome">{@exchange.outcome}</:item>
            <:item title="HTTP status">{@exchange.response_status || "—"}</:item>
            <:item title="Duration">
              {if @exchange.duration_ms, do: "#{@exchange.duration_ms} ms", else: "—"}
            </:item>
            <:item title="Time"><.datetime id="exchange-time" value={@exchange.occurred_at} /></:item>
            <:item title="Tenant">{@exchange.tenant_id || "Unknown / system"}</:item>
            <:item title="Owner">{@exchange.owner_type || "—"} {@exchange.owner_id}</:item>
            <:item title="Person">{@exchange.person_id || "—"}</:item>
            <:item title="Impersonator">{@exchange.impersonator_id || "—"}</:item>
            <:item title="Connection">{@exchange.connection_id || "—"}</:item>
            <:item title="Agent">{@exchange.agent_id || "—"}</:item>
            <:item title="Run">{@exchange.run_id || "—"}</:item>
            <:item title="Error">{@exchange.error_class || "—"}</:item>
          </.list>
        </.card>
        <.card
          id="exchange-payload-card"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="exchange-payload-heading"
        >
          <.section_heading
            id="exchange-payload-heading"
            title="Retained payload"
          >
            <:description>
              Bodies and headers are omitted by default. Retained structured previews are redacted and expire after the configured retention period.
            </:description>
          </.section_heading>
          <.button :if={@can_payload} id="exchange-view-payload" phx-click="payload">Inspect retained payload</.button>
          <.empty_state
            :if={!@can_payload}
            title="Payload inspection restricted"
            reason="Ask an administrator for the payload inspection permission."
          />
          <pre
            :if={@payload}
            id="exchange-payload"
            class="overflow-x-auto bg-surface-sunken p-2 text-xs"
          >{@payload}</pre>
        </.card>
        <.button
          :if={@can_delete}
          id="exchange-delete"
          phx-click="confirm_delete"
        >Delete exchange</.button>
        <.empty_state
          :if={!@can_delete}
          title="Deletion restricted"
          reason="Ask an administrator for the exchange deletion permission."
        />
        <.confirm_dialog
          :if={@confirming_delete}
          id="exchange-delete-confirm"
          consequence="This exchange and any retained payload will be permanently deleted."
          detail="The record cannot be restored."
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />
      </.page>
    </Layouts.app>
    """
  end
end
