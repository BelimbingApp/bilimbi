defmodule Bilimbi.Core.AgentAccess.Web.DeviceLive do
  @moduledoc "Signed-in device consent. Opening a link never approves it; confirm the code and stated agent on your own device."
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Core.AgentAccess
  # Self-service consent derives its owner from the scope, with no admin grant.
  @write_guard_opt_out ~w(lookup approve deny dismiss)
  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         device: nil,
         code: "",
         error: nil,
         form: to_form(%{"user_code" => ""}, as: :device)
       )}

  def handle_params(params, _, socket) do
    {:noreply,
     assign(socket, form: to_form(%{"user_code" => params["user_code"] || ""}, as: :device))}
  end

  def handle_event("lookup", %{"device" => %{"user_code" => code}}, socket) do
    case AgentAccess.device(socket.assigns.current_scope.scope, String.upcase(String.trim(code))) do
      {:ok, device} ->
        {:noreply,
         assign(socket,
           device: device,
           code: String.upcase(String.trim(code)),
           error: nil,
           expiry_form:
             to_form(%{"end_date" => Date.utc_today() |> Date.add(30) |> Date.to_iso8601()},
               as: :grant
             )
         )}

      {:error, reason} ->
        {:noreply, assign(socket, device: nil, error: message(reason))}
    end
  end

  def handle_event("approve", %{"grant" => %{"end_date" => date}}, socket) do
    expires =
      with {:ok, date} <- Date.from_iso8601(date),
           do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

    decide(socket, :approve, expires)
  end

  def handle_event("deny", _, socket),
    do: decide(socket, :deny, DateTime.add(DateTime.utc_now(), 60))

  def handle_event("dismiss", _, socket), do: {:noreply, assign(socket, error: nil)}

  defp decide(socket, decision, expires) do
    case AgentAccess.decide(
           socket.assigns.current_scope.scope,
           socket.assigns.code,
           decision,
           expires
         ) do
      :ok ->
        {:noreply,
         socket
         |> assign(device: nil, code: "", error: nil)
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

  defp message(:invalid_expiry), do: "Choose an end date in the future."

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
        <.form for={@form} id="device-code-form" phx-submit="lookup">
          <.input field={@form[:user_code]} label="Code shown by your agent" required />
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
          <.form for={@expiry_form} id="device-approval-form" phx-submit="approve">
            <.input
              field={@expiry_form[:end_date]}
              type="date"
              label="Connection ends (UTC)"
              required
            />
            <.button id="device-approve" type="submit">Approve connection</.button>
            <.button id="device-deny" type="button" phx-click="deny">Refuse</.button>
          </.form>
        </.card>
        <.link navigate={~p"/settings/agent-connections"}>Your connections</.link>
      </.page>
    </Layouts.app>
    """
  end
end
