defmodule BilimbiWeb.DashboardLive do
  @moduledoc """
  The workspace landing screen after sign-in.

  Renders a widget grid whose catalogue is contributed by installed modules
  through `Bilimbi.Base.Dashboard`. Widgets are rendered by their contribution
  id against known implementations of `Bilimbi.Base.Dashboard.Widget`.

  Widget visibility is gated by capability. Layout is persisted per-user in the
  `ui.dashboard.layout` setting. While editing, widgets can be reordered by
  drag (a `DashboardSort` hook pushes the new order; the server validates it is
  a permutation of the current ids before persisting) or by the keyboard move
  buttons Belimbing pairs with its own drag handles. Widgets with a non-zero
  `refresh_interval` are auto-refreshed through a `handle_info` timer.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.Perf
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias BilimbiWeb.UserAuth

  @widget_modules %{
    "base-dashboard-company-stats" => BilimbiWeb.Dashboard.CompanyStatsWidget,
    "base-dashboard-user-stats" => BilimbiWeb.Dashboard.UserStatsWidget,
    "base-dashboard-recent-audit" => BilimbiWeb.Dashboard.RecentAuditWidget,
    "base-dashboard-session-stats" => BilimbiWeb.Dashboard.SessionStatsWidget,
    "base-perf-health" => Bilimbi.Base.Perf.DashboardWidget
  }

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok, companies} = Company.list_companies(scope)
    {:ok, users} = User.list_users(scope)

    current_company =
      Enum.find(companies, &(&1.id == socket.assigns.current_scope.user["company_id"])) ||
        List.first(companies)

    full_catalogue = Dashboard.widgets()
    authorized = authorized_catalogue(full_catalogue, socket.assigns.current_scope)
    layout = user_layout(socket.assigns.current_scope)
    visible = ordered_visible(authorized, layout)
    available = available_widgets(authorized, visible)

    audit_entries = audit_entries(scope)
    session_count = session_count(visible)
    perf_diagnostics = perf_diagnostics(visible)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, nil)
     |> assign(:widgets, visible)
     |> assign(:available_widgets, available)
     |> assign(:full_catalogue, full_catalogue)
     |> assign(:company_count, length(companies))
     |> assign(:active_company_count, active_company_count(companies))
     |> assign(:user_count, length(users))
     |> assign(:verified_user_count, verified_user_count(users))
     |> assign(:unverified_user_count, unverified_user_count(users))
     |> assign(:session_count, session_count)
     |> assign(:perf_diagnostics, perf_diagnostics)
     |> assign(:audit_entries, audit_entries)
     |> assign(:companies, companies)
     |> assign(:users, users)
     |> assign(:current_company, current_company)
     |> assign(:layout_editing, false)
     |> assign(:refresh_timer, nil)
     |> schedule_refresh(visible)}
  end

  # The count backs a widget gated by `admin.system.session.list`; skip the
  # query entirely when the viewer cannot see it.
  defp session_count(visible_widgets) do
    if Enum.any?(visible_widgets, &(&1.id == "base-dashboard-session-stats")) do
      Session.count_sessions()
    else
      nil
    end
  end

  defp perf_diagnostics(visible_widgets) do
    if Enum.any?(visible_widgets, &(&1.id == "base-perf-health")) do
      Perf.diagnostics()
    else
      nil
    end
  end

  defp audit_entries(scope) do
    Audit.list_mutations(scope,
      page: 1,
      page_size: 5,
      sort_by: :occurred_at,
      sort_dir: :desc
    ).entries
  end

  defp active_company_count(companies) do
    Enum.count(companies, &(&1.status == "active"))
  end

  defp verified_user_count(users) do
    Enum.count(users, &(!is_nil(&1.email_verified_at)))
  end

  defp unverified_user_count(users) do
    Enum.count(users, &(is_nil(&1.email_verified_at)))
  end

  defp widget_module(widget_id) do
    Map.get(@widget_modules, widget_id)
  end

  defp schedule_refresh(socket, widgets) do
    if timer = socket.assigns[:refresh_timer] do
      Process.cancel_timer(timer)
    end

    intervals =
      widgets
      |> Enum.map(&widget_module(&1.id))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.widget_refresh_interval())
      |> Enum.reject(&(&1 == 0))

    timer =
      if intervals != [] do
        min_interval = Enum.min(intervals)
        Process.send_after(self(), :refresh_widgets, min_interval)
      else
        nil
      end

    assign(socket, :refresh_timer, timer)
  end

  # `ui.dashboard.layout` is declared with `default: []`, so `Settings.get/2`
  # answers `[]` both for an account that has never customised its dashboard and
  # for one that deliberately removed every widget. Reading the value alone
  # collapses those two cases and leaves every new account with an empty
  # dashboard (#359). `overridden?/2` asks the question the layout actually
  # depends on: is there a stored row for this user?
  defp user_layout(current_scope) do
    settings_scope =
      Settings.Scope.user(
        current_scope.user["user_id"],
        current_scope.user["company_id"],
        current_scope.scope.tenant.id
      )

    with true <- Settings.overridden?("ui.dashboard.layout", settings_scope),
         value when is_list(value) <- Settings.get("ui.dashboard.layout", settings_scope) do
      value
    else
      _ -> nil
    end
  end

  defp persist_layout(current_scope, widget_ids) do
    settings_scope =
      Settings.Scope.user(
        current_scope.user["user_id"],
        current_scope.user["company_id"],
        current_scope.scope.tenant.id
      )

    Settings.put("ui.dashboard.layout", widget_ids, settings_scope)
  end

  defp authorized_catalogue(catalogue, current_scope) do
    Enum.filter(catalogue, fn widget ->
      is_nil(widget.capability) or UserAuth.allowed?(current_scope, widget.capability)
    end)
  end

  defp ordered_visible(authorized_catalogue, layout) do
    case layout do
      nil ->
        authorized_catalogue

      layout_ids when is_list(layout_ids) ->
        by_id = Map.new(authorized_catalogue, &{&1.id, &1})
        Enum.flat_map(layout_ids, fn id -> if by_id[id], do: [by_id[id]], else: [] end)
    end
  end

  defp available_widgets(authorized_catalogue, visible) do
    visible_ids = MapSet.new(visible, & &1.id)
    Enum.reject(authorized_catalogue, &(&1.id in visible_ids))
  end

  @impl true
  def handle_event("add-widget", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.available_widgets, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      widget ->
        widgets = socket.assigns.widgets ++ [widget]
        available = Enum.reject(socket.assigns.available_widgets, &(&1.id == id))
        layout = Enum.map(widgets, & &1.id)
        _ = persist_layout(socket.assigns.current_scope, layout)

        {:noreply,
         socket
         |> assign(:widgets, widgets)
         |> assign(:available_widgets, available)
         |> schedule_refresh(widgets)
         |> put_flash(:info, "#{widget.label} added to dashboard.")}
    end
  end

  @impl true
  def handle_event("remove-widget", %{"id" => id}, socket) do
    case Enum.split_with(socket.assigns.widgets, &(&1.id == id)) do
      {[widget], kept} ->
        widgets = kept

        available =
          [widget | socket.assigns.available_widgets] |> Enum.sort_by(&{&1.order, &1.id})

        layout = Enum.map(widgets, & &1.id)
        _ = persist_layout(socket.assigns.current_scope, layout)

        {:noreply,
         socket
         |> assign(:widgets, widgets)
         |> assign(:available_widgets, available)
         |> schedule_refresh(widgets)
         |> put_flash(:info, "Widget removed.")}

      {[], _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move-up", %{"id" => id}, socket) do
    widgets = move_one(socket.assigns.widgets, id, -1)
    layout = Enum.map(widgets, & &1.id)
    _ = persist_layout(socket.assigns.current_scope, layout)
    {:noreply, assign(socket, :widgets, widgets)}
  end

  @impl true
  def handle_event("move-down", %{"id" => id}, socket) do
    widgets = move_one(socket.assigns.widgets, id, 1)
    layout = Enum.map(widgets, & &1.id)
    _ = persist_layout(socket.assigns.current_scope, layout)
    {:noreply, assign(socket, :widgets, widgets)}
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
      layout = Enum.map(widgets, & &1.id)
      _ = persist_layout(socket.assigns.current_scope, layout)
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

  defp move_one(widgets, id, direction) do
    case Enum.find_index(widgets, &(&1.id == id)) do
      nil ->
        widgets

      idx ->
        target = idx + direction

        if target >= 0 && target < length(widgets) do
          List.update_at(widgets, idx, fn _ -> Enum.at(widgets, target) end)
          |> List.update_at(target, fn _ -> Enum.at(widgets, idx) end)
        else
          widgets
        end
    end
  end

  @impl true
  def handle_info(:refresh_widgets, socket) do
    scope = socket.assigns.current_scope.scope

    audit_entries = audit_entries(scope)

    {:noreply,
     socket
     |> assign(:audit_entries, audit_entries)
     |> assign(:session_count, session_count(socket.assigns.widgets))
     |> assign(:perf_diagnostics, perf_diagnostics(socket.assigns.widgets))
     |> assign(:refresh_timer, nil)
     |> schedule_refresh(socket.assigns.widgets)}
  end

  @impl true
  def handle_info({:notification_event, _payload}, socket) do
    {:noreply, socket}
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
              class="rounded-lg px-3 py-1.5 text-xs font-medium shadow-none"
            >
              Customize
            </.button>
            <.button
              :if={@layout_editing}
              id="close-customize"
              phx-click="toggle-layout-edit"
              class="rounded-lg px-3 py-1.5 text-xs font-medium shadow-none"
            >
              Close
            </.button>
          </:actions>
        </.header>

        <div
          :if={@layout_editing and @available_widgets != []}
          id="add-widget-section"
          class="mb-3 flex flex-wrap items-center gap-2 rounded-xl border border-line bg-surface p-3 shadow-xs"
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
        </div>

        <div
          :if={@widgets != []}
          id="dashboard-widgets"
          phx-hook="DashboardSort"
          class="mt-4 grid grid-cols-1 gap-3 xl:grid-cols-2"
        >
          <.render_widget
            :for={widget <- @widgets}
            widget={widget}
            company_count={@company_count}
            active_company_count={@active_company_count}
            user_count={@user_count}
            verified_user_count={@verified_user_count}
            unverified_user_count={@unverified_user_count}
            current_company={@current_company}
            session_count={@session_count}
            perf_diagnostics={@perf_diagnostics}
            audit_entries={@audit_entries}
            current_scope={@current_scope}
            layout_editing={@layout_editing}
          />
        </div>

        <p :if={@widgets == []} id="dashboard-widgets-empty" class="mt-5 text-sm text-ink-subtle">
          No widgets configured.
          <.link
            phx-click="toggle-layout-edit"
            class="font-medium text-ink underline underline-offset-2 hover:text-ink-strong"
          >
            Customize dashboard
          </.link>
          &nbsp;to add widgets.
        </p>

        <section
          :if={@current_company}
          id="dashboard-current-company"
          data-company-id={@current_company.id}
          class="mt-6 overflow-hidden rounded-xl border border-line bg-surface shadow-xs shadow-ink/[0.03]"
        >
          <div class="h-0.5 bg-brand" aria-hidden="true"></div>
          <div class="flex items-center justify-between gap-4 px-5 py-4">
            <div class="min-w-0">
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
                Your company
              </p>
              <h2
                id="dashboard-company-name"
                class="mt-1 truncate text-base font-semibold text-ink-strong"
              >
                {Company.Summary.display_name(@current_company)}
              </h2>
              <p class="mt-0.5 text-xs text-ink-subtle">
                <code class="font-medium">{@current_company.code}</code>
              </p>
            </div>
            <div class="flex shrink-0 flex-col items-end gap-2">
              <.badge kind={if @current_company.status == "active", do: :success, else: :warning}>
                {@current_company.status}
              </.badge>
              <.link
                :if={UserAuth.allowed?(@current_scope, "admin.company.view")}
                navigate={~p"/companies/#{@current_company.id}"}
                id="dashboard-company-open"
                class="text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 hover:text-ink"
              >
                Open company
              </.link>
            </div>
          </div>
        </section>

        <section id="dashboard-recent-users" class="mt-6">
          <div class="mb-2 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-ink-strong">People in this workspace</h2>
            <.link
              :if={UserAuth.allowed?(@current_scope, "admin.user.list")}
              navigate={~p"/users"}
              class="text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 hover:text-ink"
            >
              All users
            </.link>
          </div>
          <.table
            id="dashboard-users"
            rows={Enum.take(@users, 5)}
            row_id={&"dashboard-user-#{&1.id}"}
            caption="People in this workspace"
          >
            <:col :let={user} label="Name">
              <span class="font-medium">{user.name}</span>
            </:col>
            <:col :let={user} label="Email">{user.email}</:col>
            <:col :let={user} label="Email verified">
              <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
                {if user.email_verified_at, do: "verified", else: "unverified"}
              </.badge>
            </:col>
            <:empty :if={@users == []}>
              No users are affiliated with a company in this tenant yet.
            </:empty>
          </.table>
        </section>
      </.page>
    </Layouts.app>
    """
  end

  defp render_widget(%{widget: widget} = assigns) do
    assigns = assign(assigns, :id, widget.id)

    ~H"""
    <div class="relative" id={"widget-#{@id}"} data-widget-id={@id}>
      <div class="absolute right-1 top-1 z-10 flex gap-0.5">
        <button
          id={"drag-#{@id}"}
          type="button"
          draggable="true"
          data-role="drag-handle"
          title="Drag to reorder. Changes save when dropped."
          aria-label={"Drag to reorder #{@widget.label}"}
          class="grid size-5 cursor-grab touch-none place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong active:cursor-grabbing"
        >
          <.icon name="hero-bars-3" class="size-3" />
        </button>
        <div :if={@layout_editing} class="flex gap-0.5">
        <button
          id={"move-up-#{@id}"}
          type="button"
          phx-click="move-up"
          phx-value-id={@id}
          title="Move up"
          class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <.icon name="hero-chevron-up" class="size-3" />
        </button>
        <button
          id={"move-down-#{@id}"}
          type="button"
          phx-click="move-down"
          phx-value-id={@id}
          title="Move down"
          class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <.icon name="hero-chevron-down" class="size-3" />
        </button>
        <button
          id={"remove-#{@id}"}
          type="button"
          phx-click="remove-widget"
          phx-value-id={@id}
          title="Remove widget"
          class="ml-1 grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-danger-surface hover:text-danger focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <.icon name="hero-x-mark" class="size-3" />
        </button>
        </div>
      </div>

      <%= case @id do %>
        <% "base-dashboard-company-stats" -> %>
          <.company_stat_card
            id="stat-companies"
            count={@company_count}
            active_count={@active_company_count}
            current_code={@current_company && @current_company.code}
            navigate={
              if UserAuth.allowed?(@current_scope, "admin.company.list"),
                do: ~p"/companies"
            }
          />
        <% "base-dashboard-user-stats" -> %>
          <.user_stat_card
            id="stat-users"
            count={@user_count}
            verified_count={@verified_user_count}
            unverified_count={@unverified_user_count}
            navigate={
              if UserAuth.allowed?(@current_scope, "admin.user.list"),
                do: ~p"/users"
            }
          />
        <% "base-dashboard-session-stats" -> %>
          <.session_stat_card
            id="stat-sessions"
            count={@session_count}
            navigate={
              if UserAuth.allowed?(@current_scope, "admin.system.session.list"),
                do: "/system/sessions"
            }
          />
        <% "base-dashboard-recent-audit" -> %>
          <.audit_activity_card
            id="stat-recent-audit"
            entries={@audit_entries}
            navigate={
              if UserAuth.allowed?(@current_scope, "admin.audit.log.list"),
                do: ~p"/audit/mutations"
            }
          />
        <% "base-perf-health" -> %>
          <.link
            navigate="/system/performance"
            id="stat-performance"
            class="group block rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong hover:bg-gradient-to-b hover:from-surface hover:to-brand-surface hover:shadow-sm"
          >
            <div class="flex items-center justify-between gap-3">
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
                Performance
              </p>
              <.action_arrow_icon />
            </div>
            <div class="mt-2.5 grid grid-cols-2 divide-x divide-line">
              <div class="pr-3">
                <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Health</p>
                <p class="mt-1 text-sm font-semibold text-ink-strong">
                  {performance_health(@perf_diagnostics)}
                </p>
              </div>
              <div class="pl-3">
                <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Samples</p>
                <p class="mt-1 text-sm font-semibold tabular-nums text-ink-strong">
                  {performance_samples(@perf_diagnostics)}
                </p>
              </div>
            </div>
          </.link>
        <% other_id -> %>
          <div
            id={"dashboard-widget-#{other_id}"}
            class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
          >
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
              {@widget.label}
            </p>
          </div>
      <% end %>
    </div>
    """
  end

  defp performance_health(%{store: :unavailable}), do: "History unavailable"
  defp performance_health(%{recorder: :unavailable}), do: "Recorder unavailable"
  defp performance_health(%{recorder: :degraded, store: :available}), do: "Degraded"
  defp performance_health(%{recorder: :available, store: :available}), do: "Available"
  defp performance_health(_diagnostics), do: "Unknown"

  defp performance_samples(%{samples: samples}) when is_integer(samples), do: samples
  defp performance_samples(_diagnostics), do: "—"

  attr(:id, :string, required: true)
  attr(:count, :integer, required: true)
  attr(:active_count, :integer, required: true)
  attr(:current_code, :string, default: nil)
  attr(:navigate, :string, default: nil)

  defp company_stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group block rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong hover:bg-gradient-to-b hover:from-surface hover:to-brand-surface hover:shadow-sm"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
          Companies
        </p>
        <.action_arrow_icon />
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Total</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Active</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@active_count}</p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Current</p>
          <p class="mt-1 truncate text-sm font-semibold text-ink-strong">{@current_code || "—"}</p>
        </div>
      </div>
    </.link>
    """
  end

  defp company_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03]"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
          Companies
        </p>
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Total</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Active</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@active_count}</p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Current</p>
          <p class="mt-1 truncate text-sm font-semibold text-ink-strong">{@current_code || "—"}</p>
        </div>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:count, :integer, required: true)
  attr(:verified_count, :integer, required: true)
  attr(:unverified_count, :integer, required: true)
  attr(:navigate, :string, default: nil)

  defp user_stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group block rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong hover:bg-gradient-to-b hover:from-surface hover:to-brand-surface hover:shadow-sm"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">Users</p>
        <.action_arrow_icon />
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Total</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Verified</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">
            {@verified_count}
          </p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Pending</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">
            {@unverified_count}
          </p>
        </div>
      </div>
    </.link>
    """
  end

  defp user_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03]"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">Users</p>
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Total</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Verified</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">
            {@verified_count}
          </p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Pending</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">
            {@unverified_count}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:count, :integer, required: true)
  attr(:navigate, :string, default: nil)

  # The sessions screen is contributed by Base Session and injected through
  # discovered routes, so its href is a plain string rather than a `~p` route.
  defp session_stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group block rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong hover:bg-gradient-to-b hover:from-surface hover:to-brand-surface hover:shadow-sm"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
          Sessions
        </p>
        <.action_arrow_icon />
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Open</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Store</p>
          <p class="mt-1 text-sm font-semibold text-ink-strong">Durable</p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Scope</p>
          <p class="mt-1 text-sm font-semibold text-ink-strong">Platform</p>
        </div>
      </div>
    </.link>
    """
  end

  defp session_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-3.5 py-3 shadow-xs shadow-ink/[0.03]"
    >
      <div class="flex items-center justify-between gap-3">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink">
          Sessions
        </p>
      </div>
      <div class="mt-2.5 grid grid-cols-3 divide-x divide-line">
        <div class="pr-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Open</p>
          <p class="mt-1 text-xl font-semibold tabular-nums text-ink-strong">{@count}</p>
        </div>
        <div class="px-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Store</p>
          <p class="mt-1 text-sm font-semibold text-ink-strong">Durable</p>
        </div>
        <div class="pl-3">
          <p class="text-[0.65rem] uppercase tracking-[0.12em] text-ink-faint">Scope</p>
          <p class="mt-1 text-sm font-semibold text-ink-strong">Platform</p>
        </div>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:entries, :list, required: true)
  attr(:navigate, :string, default: nil)

  defp audit_activity_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-xl border border-line bg-surface shadow-xs shadow-ink/[0.03]">
      <div class="flex items-center justify-between border-b border-line px-4 py-3">
        <h3 class="text-[0.7rem] font-semibold uppercase tracking-[0.14em] text-ink">
          Recent Activity
        </h3>
        <.link
          :if={@navigate}
          navigate={@navigate}
          class="text-brand-strong transition hover:text-brand"
        >
          <.action_arrow_icon />
        </.link>
      </div>
      <div :if={Enum.empty?(@entries)} class="px-4 py-5 text-sm text-ink-subtle">
        No recent activity.
      </div>
      <div :if={Enum.any?(@entries)} class="divide-y divide-line">
        <div
          :for={entry <- @entries}
          class="flex items-start gap-3 px-4 py-2.5 text-sm"
        >
          <.icon name="hero-document-text" class="size-4 shrink-0 text-ink-faint" />
          <div class="min-w-0 flex-1">
            <span class="font-medium text-ink">{entry.event}</span>
            <span class="ml-2 text-ink-subtle">{entry.auditable_type}</span>
          </div>
          <.datetime
            id={"audit-entry-#{entry.id}"}
            value={entry.occurred_at}
            class="text-xs tabular-nums text-ink-faint"
          />
        </div>
      </div>
    </div>
    """
  end

  defp action_arrow_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
      class="size-4 shrink-0 text-brand-strong transition group-hover:translate-x-0.5"
    >
      <path d="M3 10a.75.75 0 0 1 .75-.75h10.638L10.23 5.29a.75.75 0 1 1 1.04-1.08l5.5 5.25a.75.75 0 0 1 0 1.08l-5.5 5.25a.75.75 0 1 1-1.04-1.08l4.158-3.96H3.75A.75.75 0 0 1 3 10Z" />
    </svg>
    """
  end
end
