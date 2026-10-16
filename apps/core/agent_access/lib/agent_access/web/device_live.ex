defmodule Bilimbi.Core.AgentAccess.Web.DeviceLive do
  @moduledoc "Signed-in device consent. Opening a link never approves it; confirm the code and stated agent on your own device."
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Core.AgentAccess
  # Self-service consent derives its owner from the scope, with no admin grant.
  @write_guard_opt_out ~w(lookup approve deny dismiss another)
  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         device: nil,
         completed: nil,
         code: "",
         error: nil,
         form: to_form(%{"user_code" => ""}, as: :device)
       )}

  def handle_params(params, _, socket) do
    {:noreply,
     assign(socket, form: to_form(%{"user_code" => params["user_code"] || ""}, as: :device))}
  end

  def handle_event("lookup", %{"device" => %{"user_code" => code}}, socket) do
    code = AgentAccess.normalize_user_code(code)
    socket = assign(socket, form: to_form(%{"user_code" => code}, as: :device))

    case AgentAccess.device(socket.assigns.current_scope.scope, code) do
      {:ok, device} ->
        {:noreply,
         assign(socket,
           device: device,
           code: code,
           error: nil,
           expires_at: AgentAccess.connection_expiry()
         )}

      {:error, reason} ->
        {:noreply, assign(socket, device: nil, error: message(reason))}
    end
  end

  def handle_event("approve", params, socket) do
    # Expiry belongs to server state. Reject old or forged date-bearing forms.
    if params == %{} do
      decide(socket, :approve)
    else
      {:noreply, assign(socket, error: message(:invalid_expiry))}
    end
  end

  def handle_event("deny", _, socket), do: decide(socket, :deny)

  def handle_event("another", _, socket) do
    {:noreply,
     socket
     |> assign(
       device: nil,
       completed: nil,
       code: "",
       error: nil,
       form: to_form(%{"user_code" => ""}, as: :device)
     )
     |> push_patch(to: ~p"/oauth/device")}
  end

  def handle_event("dismiss", _, socket), do: {:noreply, assign(socket, error: nil)}

  defp decide(%{assigns: %{device: nil}} = socket, _decision), do: {:noreply, socket}

  defp decide(socket, decision) do
    case AgentAccess.decide(
           socket.assigns.current_scope.scope,
           socket.assigns.code,
           decision,
           socket.assigns.expires_at
         ) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           device: nil,
           code: "",
           error: nil,
           completed: %{
             decision: decision,
             agent_id: socket.assigns.device.agent_id,
             expires_at: socket.assigns.expires_at
           }
         )
         |> put_flash(
           :success,
           if(decision == :approve, do: "Agent connected.", else: "Connection refused.")
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: message(reason))}
    end
  end

  defp message(:person_required),
    do: "Connect from your own signed-in account. Impersonation cannot approve connections."

  defp message(:invalid_expiry),
    do: "The connection end time cannot be changed here. Check the code again."

  defp message(_),
    do: "This code expired or has already been used. Request a new code from your agent."

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={nil}>
      <.page variant={:form}>
        <.header>Connect an agent</.header>
        <.panel_notice :if={@error} kind={:error} on_dismiss={JS.push("dismiss")} id="device-error">
          {@error}
        </.panel_notice>
        <.form :if={!@completed} for={@form} id="device-code-form" phx-submit="lookup">
          <.code_input
            field={@form[:user_code]}
            label="Code shown by your agent"
            length={8}
            group_size={4}
          />
          <.button id="device-lookup" type="submit">Check code</.button>
        </.form>
        <.card :if={@device} id="device-consent" class="mt-4">
          <.section_heading title="Review connection" />
          <.list>
            <:item title="Code">{@code}</:item>
            <:item title="Stated agent">{@device.agent_id}</:item>
          </.list>
          <p class="text-sm text-muted">
            Approve only a code you requested. The agent acts as you in your current company, with your current read permissions. The stated name does not prove who runs the agent.
          </p>
          <p id="device-connection-end" class="text-sm text-muted">
            Connection ends <.datetime id="device-expiry" value={@expires_at} />.
          </p>
          <.form for={%{}} id="device-approval-form" phx-submit="approve">
            <.button id="device-approve" type="submit">Approve connection</.button>
            <.button id="device-deny" type="button" phx-click="deny">Refuse</.button>
          </.form>
        </.card>
        <.card :if={@completed} id="device-completed" class="mt-4">
          <div role="status">
            <.section_heading title={
              if @completed.decision == :approve, do: "Agent connected", else: "Connection refused"
            } />
            <p id="device-completed-agent" class="text-sm text-ink">{@completed.agent_id}</p>
            <p
              :if={@completed.decision == :approve}
              id="device-completed-end"
              class="text-sm text-muted"
            >
              Connection ends
              <.datetime id="device-completed-expiry" value={@completed.expires_at} />.
            </p>
            <p class="text-sm text-muted">You can go back to your agent.</p>
          </div>
          <.button id="device-another" phx-click="another">Connect another device</.button>
        </.card>
        <.link id="device-connections" navigate={~p"/settings/agent-connections"}>Your connections</.link>
      </.page>
    </Layouts.app>
    """
  end
end
