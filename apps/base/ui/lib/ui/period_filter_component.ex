defmodule Bilimbi.Base.UI.PeriodFilterComponent do
  @moduledoc false
  use Bilimbi.Base.UI, :live_component
  alias Bilimbi.Base.UI.PeriodFilter

  @write_guard_opt_out ~w(select open cancel apply draft)

  @impl true
  def mount(socket), do: {:ok, assign(socket, open?: false, error: nil)}

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("select", %{"period_filter" => %{"period" => period}}, socket)
      when period in ["custom", "change_custom"],
      do: open(socket)

  def handle_event("select", %{"period_filter" => %{"period" => period}}, socket) do
    patch(socket, PeriodFilter.parse(%{"period" => period}, socket.assigns.clock.today))
  end

  def handle_event("open", _, socket), do: open(socket)
  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, open?: false, error: nil)}

  def handle_event("draft", %{"range" => values}, socket),
    do: {:noreply, assign(socket, draft: to_form(values, as: :range))}

  def handle_event("apply", %{"range" => %{"from" => from, "to" => to}}, socket) do
    case PeriodFilter.custom(from, to) do
      {:ok, state} ->
        patch(socket, state)

      {:error, error} ->
        {:noreply,
         assign(socket, error: error, draft: to_form(%{"from" => from, "to" => to}, as: :range))}
    end
  end

  def report_action_failure(socket, message), do: assign(socket, :error, message)

  defp open(socket) do
    {:noreply,
     assign(socket,
       open?: true,
       error: nil,
       draft:
         to_form(Map.take(PeriodFilter.params(socket.assigns.state), ["from", "to"]), as: :range)
     )}
  end

  defp patch(socket, state) do
    {:noreply,
     socket
     |> assign(open?: false, error: nil)
     |> push_patch(to: socket.assigns.path.(PeriodFilter.params(state)))}
  end

  # Give the select a different rendered value while editing so LiveView
  # restores the applied option on Cancel, even when editing an existing range.
  defp selected_period(%{open?: true, state: %{period: "custom"}}), do: "change_custom"
  defp selected_period(%{open?: true}), do: "custom"
  defp selected_period(%{state: state}), do: state.period

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :selection,
        to_form(%{"period" => selected_period(assigns)},
          as: :period_filter
        )
      )

    ~H"""
    <div id={@id} class="w-full sm:w-40">
      <.form
        for={@selection}
        id={"#{@id}-selection"}
        phx-change="select"
        phx-submit="select"
        phx-target={@myself}
      >
        <.input
          field={@selection[:period]}
          id={"#{@id}-period"}
          type="select"
          label={@label}
          label_class="sr-only"
          wrapper_class="mb-0"
          options={
            PeriodFilter.options() ++
              if(@state.period == "custom", do: [{"Change dates…", "change_custom"}], else: [])
          }
          title={"#{@state.from} – #{@state.to} (#{@clock.timezone})"}
        />
      </.form>
      <.modal
        :if={@open?}
        id={"#{@id}-range"}
        title="Custom date range"
        width={:compact}
        on_cancel={JS.push("cancel", target: @myself)}
      >
        <:description>Choose the first and last dates to include.</:description>
        <.form
          for={@draft}
          id={"#{@id}-range-form"}
          phx-change="draft"
          phx-submit="apply"
          phx-target={@myself}
          class="mt-4 space-y-4"
        >
          <p :if={@error} id={"#{@id}-range-error"} role="alert" class="text-sm text-danger-ink">
            {@error}
          </p>
          <div class="grid gap-3 sm:grid-cols-2">
            <.input field={@draft[:from]} id={"#{@id}-draft-from"} type="date" label="From" required />
            <.input field={@draft[:to]} id={"#{@id}-draft-to"} type="date" label="To" required />
          </div>
          <div class="flex justify-end gap-2">
            <.button id={"#{@id}-cancel"}  phx-click="cancel" phx-target={@myself}>Cancel</.button>
            <.button id={"#{@id}-apply"} type="submit">Apply range</.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
