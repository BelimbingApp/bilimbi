defmodule Bilimbi.Base.Dashboard.Web.IndexLive do
  @moduledoc """
  The workspace landing screen after sign-in.

  The page owns the arrangement and nothing else. The catalogue is what
  installed modules contribute through `Bilimbi.Base.Dashboard`: grid widgets
  and the full-width sections below them. Each entry is drawn by the
  embeddable panel its owner declares, rendered here with
  `<.discovered_panel>`, so this module names no owner and reads no owner's
  data.

  Entry visibility is gated by capability. The arrangement is persisted per
  user in the `ui.dashboard.layout` and `ui.dashboard.sections` settings.
  While editing, widgets can be reordered by drag (a `DashboardSort` hook
  pushes the new order; the server validates it is a permutation of the
  current ids before persisting) or by the keyboard move buttons Belimbing
  pairs with its own drag handles. A visible entry with a non-zero
  `refresh_interval` makes the page count a refresh once the socket is
  connected. Every panel receives that count and whether the socket is
  connected, and decides for itself whether to read.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.Settings

  @dashboard_layout_key "ui.dashboard.layout"
  @dashboard_sections_key "ui.dashboard.sections"

  # These customize the signed-in actor's own dashboard preference. They are
  # self-service settings writes, not privileged administration writes (#376).
  # `toggle-layout-edit` only flips the customize-mode assign; the widget
  # events persist through `persist/3` to the actor's own user settings scope
  # (#420).
  @write_guard_opt_out ~w(add-section remove-section move-section-up move-section-down
                          add-widget remove-widget move-up move-down reorder-widgets
                          toggle-layout-edit)

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope

    full_catalogue = Dashboard.widgets()
    catalogue = authorized(full_catalogue, current_scope)
    widgets = arranged(catalogue, stored(@dashboard_layout_key, current_scope))

    section_catalogue = authorized(Dashboard.sections(), current_scope)
    sections = arranged(section_catalogue, stored(@dashboard_sections_key, current_scope))

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, nil)
     |> assign(:full_catalogue, full_catalogue)
     |> assign(:catalogue, catalogue)
     |> assign(:section_catalogue, section_catalogue)
     |> assign(:layout_editing, false)
     |> assign(:refresh, 0)
     |> assign(:refresh_timer, nil)
     |> assign(:connected, Phoenix.LiveView.connected?(socket))
     |> assign_widgets(widgets)
     |> assign_sections(sections)}
  end

  defp assign_widgets(socket, widgets) do
    socket
    |> assign(:widgets, widgets)
    |> assign(:available_widgets, socket.assigns.catalogue -- widgets)
    |> schedule_refresh()
  end

  defp assign_sections(socket, sections) do
    socket
    |> assign(:sections, sections)
    |> assign(:available_sections, socket.assigns.section_catalogue -- sections)
    |> schedule_refresh()
  end

  # One timer at the shortest interval any visible entry asks for. The
  # disconnected render exits with the response, so it does not start one.
  defp schedule_refresh(%{assigns: %{connected: false}} = socket), do: socket

  defp schedule_refresh(socket) do
    if timer = socket.assigns[:refresh_timer] do
      Process.cancel_timer(timer)
    end

    intervals =
      (socket.assigns[:widgets] || [])
      |> Enum.concat(socket.assigns[:sections] || [])
      |> Enum.map(& &1.refresh_interval)
      |> Enum.reject(&(&1 == 0))

    timer =
      if intervals != [] do
        Process.send_after(self(), :refresh_widgets, Enum.min(intervals))
      else
        nil
      end

    assign(socket, :refresh_timer, timer)
  end

  # Both settings are declared with `default: []`, so `Settings.get/2` answers
  # `[]` both for an account that has never customised its dashboard and for
  # one that deliberately removed everything. Reading the value alone collapses
  # those two cases and leaves every new account with an empty dashboard
  # (#359). `overridden?/2` asks the question the arrangement actually depends
  # on: is there a stored row for this user?
  defp stored(key, current_scope) do
    settings_scope = user_settings_scope(current_scope)

    with true <- Settings.overridden?(key, settings_scope),
         value when is_list(value) <- Settings.get(key, settings_scope) do
      value
    else
      _ -> nil
    end
  end

  defp persist(key, current_scope, entries) do
    Settings.put(key, Enum.map(entries, & &1.id), user_settings_scope(current_scope))
  end

  defp user_settings_scope(current_scope) do
    Settings.Scope.user(
      current_scope.user["user_id"],
      current_scope.user["company_id"],
      current_scope.scope.tenant.id
    )
  end

  # Completes `<.empty_state forbidden>` into "You do not have permission to
  # ...", naming each capability the withheld widgets require in the key form
  # the Roles and Capabilities pages use. Only reached when every widget the
  # catalogue holds was withheld, so each one carries a capability.
  defp withheld_widgets_wording(catalogue) do
    case catalogue |> Enum.map(& &1.capability) |> Enum.uniq() |> Enum.sort() do
      [capability] ->
        "see the dashboard widgets, each of which needs #{capability}"

      capabilities ->
        {rest, [last]} = Enum.split(capabilities, -1)

        "see the dashboard widgets; each widget needs its own permission, and these widgets use #{Enum.join(rest, ", ")} and #{last}"
    end
  end

  defp authorized(catalogue, current_scope) do
    Enum.filter(catalogue, fn entry ->
      is_nil(entry.capability) or allowed?(current_scope, entry.capability)
    end)
  end

  # No stored arrangement shows the whole authorized catalogue. A stored one
  # keeps its order and drops ids this account can no longer see.
  defp arranged(catalogue, nil), do: catalogue

  defp arranged(catalogue, ids) when is_list(ids) do
    by_id = Map.new(catalogue, &{&1.id, &1})
    Enum.flat_map(ids, fn id -> if by_id[id], do: [by_id[id]], else: [] end)
  end

  @impl true
  def handle_event("add-widget", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.available_widgets, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      widget ->
        widgets = socket.assigns.widgets ++ [widget]
        _ = persist(@dashboard_layout_key, socket.assigns.current_scope, widgets)

        {:noreply,
         socket
         |> assign_widgets(widgets)
         |> put_flash(:success, "#{widget.label} added to dashboard.")}
    end
  end

  @impl true
  def handle_event("remove-widget", %{"id" => id}, socket) do
    case Enum.split_with(socket.assigns.widgets, &(&1.id == id)) do
      {[_widget], widgets} ->
        _ = persist(@dashboard_layout_key, socket.assigns.current_scope, widgets)

        {:noreply,
         socket
         |> assign_widgets(widgets)
         |> put_flash(:success, "Widget removed.")}

      {[], _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add-section", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.available_sections, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      section ->
        sections = socket.assigns.sections ++ [section]
        _ = persist(@dashboard_sections_key, socket.assigns.current_scope, sections)

        {:noreply,
         socket
         |> assign_sections(sections)
         |> put_flash(:success, "#{section.label} added to dashboard.")}
    end
  end

  @impl true
  def handle_event("remove-section", %{"id" => id}, socket) do
    case Enum.split_with(socket.assigns.sections, &(&1.id == id)) do
      {[section], sections} ->
        _ = persist(@dashboard_sections_key, socket.assigns.current_scope, sections)

        {:noreply,
         socket
         |> assign_sections(sections)
         |> put_flash(:success, "#{section.label} removed from dashboard.")}

      {[], _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move-section-up", %{"id" => id}, socket) do
    move_section(socket, id, -1)
  end

  @impl true
  def handle_event("move-section-down", %{"id" => id}, socket) do
    move_section(socket, id, 1)
  end

  @impl true
  def handle_event("move-up", %{"id" => id}, socket) do
    move_widget(socket, id, -1)
  end

  @impl true
  def handle_event("move-down", %{"id" => id}, socket) do
    move_widget(socket, id, 1)
  end

  # The drag hook pushes the DOM order after a drop. The browser is not the
  # source of truth: an order that is not exactly a permutation of the current
  # widget ids (stale patch, forged push) is ignored, never persisted.
  @impl true
  def handle_event("reorder-widgets", %{"ids" => ids}, socket) when is_list(ids) do
    widgets = reordered(socket.assigns.widgets, ids)

    if widgets == socket.assigns.widgets do
      {:noreply, socket}
    else
      _ = persist(@dashboard_layout_key, socket.assigns.current_scope, widgets)
      {:noreply, assign(socket, :widgets, widgets)}
    end
  end

  def handle_event("reorder-widgets", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle-layout-edit", _params, socket) do
    {:noreply, assign(socket, :layout_editing, !socket.assigns.layout_editing)}
  end

  defp reordered(widgets, ids) do
    current_ids = Enum.map(widgets, & &1.id)

    if length(ids) == length(current_ids) and MapSet.new(ids) == MapSet.new(current_ids) do
      by_id = Map.new(widgets, &{&1.id, &1})
      Enum.map(ids, &Map.fetch!(by_id, &1))
    else
      widgets
    end
  end

  defp move_widget(socket, id, direction) do
    widgets = move_one(socket.assigns.widgets, id, direction)

    if widgets == socket.assigns.widgets do
      {:noreply, socket}
    else
      _ = persist(@dashboard_layout_key, socket.assigns.current_scope, widgets)
      {:noreply, assign(socket, :widgets, widgets)}
    end
  end

  defp move_section(socket, id, direction) do
    sections = move_one(socket.assigns.sections, id, direction)

    if sections == socket.assigns.sections do
      {:noreply, socket}
    else
      _ = persist(@dashboard_sections_key, socket.assigns.current_scope, sections)
      {:noreply, assign(socket, :sections, sections)}
    end
  end

  defp move_one(entries, id, direction) do
    case Enum.find_index(entries, &(&1.id == id)) do
      nil ->
        entries

      idx ->
        target = idx + direction

        if target >= 0 && target < length(entries) do
          List.update_at(entries, idx, fn _ -> Enum.at(entries, target) end)
          |> List.update_at(target, fn _ -> Enum.at(entries, idx) end)
        else
          entries
        end
    end
  end

  @impl true
  def handle_info(:refresh_widgets, socket) do
    {:noreply,
     socket
     |> update(:refresh, &(&1 + 1))
     |> assign(:refresh_timer, nil)
     |> schedule_refresh()}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          Dashboard
          <:subtitle>
            {@current_scope.scope.tenant.name} · {@current_scope.user["name"]}
          </:subtitle>
          <:actions>
            <.button
              :if={!@layout_editing}
              id="customize-layout"
              phx-click="toggle-layout-edit"
            >
              Customize
            </.button>
            <.button
              :if={@layout_editing}
              id="close-customize"
              phx-click="toggle-layout-edit"
            >
              Close
            </.button>
          </:actions>
        </.header>

        <.card
          :if={@layout_editing and (@available_widgets != [] or @available_sections != [])}
          id="add-widget-section"
          class="mb-3"
          inner_class="flex flex-wrap items-center gap-2 p-3"
        >
          <span class="text-xs font-semibold text-ink-muted">Customize dashboard:</span>
          <button
            :for={w <- @available_widgets}
            id={"add-widget-#{w.id}"}
            type="button"
            phx-click="add-widget"
            phx-value-id={w.id}
            class="rounded-md border border-line bg-surface-sunken px-2 py-1 text-xs font-medium text-ink transition hover:bg-surface hover:text-ink-strong"
          >
            + {w.label}
          </button>
          <button
            :for={section <- @available_sections}
            id={"add-section-#{section.id}"}
            type="button"
            phx-click="add-section"
            phx-value-id={section.id}
            class="rounded-md border border-line bg-surface-sunken px-2 py-1 text-xs font-medium text-ink transition hover:bg-surface hover:text-ink-strong"
          >
            + {section.label}
          </button>
        </.card>

        <div
          :if={@widgets != []}
          id="dashboard-widgets"
          phx-hook="DashboardSort"
          data-sort-enabled={to_string(@layout_editing)}
          class="mt-4 grid grid-cols-1 gap-3 xl:grid-cols-2"
        >
          <div
            :for={widget <- @widgets}
            class="relative"
            id={"widget-#{widget.id}"}
            data-widget-id={widget.id}
          >
            <div :if={@layout_editing} class="absolute right-1 top-1 z-10 flex gap-0.5">
              <.icon_button
                icon="hero-bars-3"
                label={"Drag to reorder #{widget.label}"}
                context={:inline}
                id={"drag-#{widget.id}"}
                draggable="true"
                data-role="drag-handle"
                title="Drag to reorder. Changes save when dropped."
                class="cursor-grab touch-none active:cursor-grabbing"
              />
              <div class="flex gap-0.5">
                <.icon_button
                  icon="hero-chevron-up"
                  label={"Move #{widget.label} up"}
                  context={:inline}
                  id={"move-up-#{widget.id}"}
                  phx-click="move-up"
                  phx-value-id={widget.id}
                  title="Move up"
                />
                <.icon_button
                  icon="hero-chevron-down"
                  label={"Move #{widget.label} down"}
                  context={:inline}
                  id={"move-down-#{widget.id}"}
                  phx-click="move-down"
                  phx-value-id={widget.id}
                  title="Move down"
                />
                <.icon_button
                  icon="close"
                  label={"Remove #{widget.label}"}
                  context={:inline}
                  kind={:danger}
                  id={"remove-#{widget.id}"}
                  phx-click="remove-widget"
                  phx-value-id={widget.id}
                  title="Remove widget"
                  class="ml-1"
                />
              </div>
            </div>
            <.discovered_panel
              key={widget.embed}
              id={"dashboard-panel-#{widget.id}"}
              current_scope={@current_scope}
              opts={%{editing: @layout_editing, refresh: @refresh, connected: @connected}}
            />
          </div>
        </div>

        <%!-- An empty grid has three causes and each asks something different
             of the reader: widgets are available but none is placed; every
             contributed widget is withheld by capability; or no module
             contributes any. Only the first is recovered by Customize. --%>
        <.empty_state
          :if={@widgets == [] and @available_widgets != []}
          id="dashboard-widgets-empty"
          class="mt-5"
          title="No widgets configured."
          reason="Add widgets from the catalogue."
        >
          <:action>
            <.button id="dashboard-widgets-customize" phx-click="toggle-layout-edit">
              Customize dashboard
            </.button>
          </:action>
        </.empty_state>

        <.empty_state
          :if={@widgets == [] and @available_widgets == [] and @full_catalogue != []}
          id="dashboard-widgets-withheld"
          class="mt-5"
          forbidden={withheld_widgets_wording(@full_catalogue)}
        />

        <.empty_state
          :if={@full_catalogue == []}
          id="dashboard-widgets-none"
          class="mt-5"
          title="No installed module contributes dashboard widgets."
        />

        <div
          :for={section <- @sections}
          id={"section-#{section.id}"}
          data-section-id={section.id}
          class="relative mt-6"
        >
          <div :if={@layout_editing} class="absolute right-1 top-1 z-10 flex gap-0.5">
            <.icon_button
              icon="hero-chevron-up"
              label={"Move #{section.label} up"}
              context={:inline}
              id={"move-section-up-#{section.id}"}
              phx-click="move-section-up"
              phx-value-id={section.id}
              title="Move up"
            />
            <.icon_button
              icon="hero-chevron-down"
              label={"Move #{section.label} down"}
              context={:inline}
              id={"move-section-down-#{section.id}"}
              phx-click="move-section-down"
              phx-value-id={section.id}
              title="Move down"
            />
            <.icon_button
              icon="close"
              label={"Remove #{section.label}"}
              context={:inline}
              kind={:danger}
              id={"remove-section-#{section.id}"}
              phx-click="remove-section"
              phx-value-id={section.id}
              title="Remove section"
            />
          </div>
          <.discovered_panel
            key={section.embed}
            id={"dashboard-panel-#{section.id}"}
            current_scope={@current_scope}
            opts={%{editing: @layout_editing, refresh: @refresh, connected: @connected}}
          />
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
