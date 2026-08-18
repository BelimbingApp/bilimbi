defmodule BilimbiWeb.DashboardLive do
  @moduledoc """
  The workspace landing screen after sign-in.

  Renders a widget grid whose catalogue is contributed by installed modules
  through `Bilimbi.Base.Dashboard`. The widget catalogue determines which
  widgets appear; this LiveView owns the rendering.

  Widget visibility is gated by capability. Widget ordering reads the
  `ui.dashboard.layout` user setting when present and falls back to the
  catalogue order. Adding, removing, and reordering widgets through the UI
  is deferred to a subsequent delivery.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias BilimbiWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok, companies} = Company.list_companies(scope)
    {:ok, users} = User.list_users(scope)

    current_company =
      Enum.find(companies, &(&1.id == socket.assigns.current_scope.user["company_id"])) ||
        List.first(companies)

    catalogue = Dashboard.widgets()
    layout = user_layout(socket.assigns.current_scope)
    visible = ordered_visible(catalogue, layout, socket)

    session_count =
      try do
        length(Session.list_sessions(limit: 500))
      rescue
        _ -> 0
      end

    audit_page =
      try do
        Audit.list_mutations(scope,
          page: 1,
          page_size: 5,
          sort_by: :occurred_at,
          sort_dir: :desc
        )
      rescue
        _ -> %{entries: []}
      end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, nil)
     |> assign(:widgets, visible)
     |> assign(:company_count, length(companies))
     |> assign(:user_count, length(users))
     |> assign(:session_count, session_count)
     |> assign(:audit_entries, audit_page.entries)
     |> assign(:companies, companies)
     |> assign(:users, users)
     |> assign(:current_company, current_company)}
  end

  defp user_layout(current_scope) do
    settings_scope =
      Settings.Scope.user(
        current_scope.user["user_id"],
        current_scope.user["company_id"],
        current_scope.scope.tenant.id
      )

    case Settings.get("ui.dashboard.layout", settings_scope) do
      value when is_list(value) -> value
      _ -> nil
    end
  rescue
    _ ->
      # The Settings table may not exist in test sandboxes or during
      # early adoption; fall back to catalogue order.
      nil
  end

  defp ordered_visible(catalogue, layout, socket) do
    scope = socket.assigns.current_scope

    visible =
      catalogue
      |> Enum.filter(fn widget ->
        is_nil(widget.capability) or UserAuth.allowed?(scope, widget.capability)
      end)

    case layout do
      nil ->
        visible

      layout_ids when is_list(layout_ids) ->
        by_id = Map.new(visible, &{&1.id, &1})
        Enum.flat_map(layout_ids, fn id -> if by_id[id], do: [by_id[id]], else: [] end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          Dashboard
          <:subtitle>
            Signed in as {@current_scope.user["name"]} · {@current_scope.scope.tenant.name}
          </:subtitle>
        </.header>

        <div
          :if={@widgets != []}
          id="dashboard-widgets"
          class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3"
        >
          <.render_widget
            :for={widget <- @widgets}
            widget={widget}
            company_count={@company_count}
            user_count={@user_count}
            session_count={@session_count}
            audit_entries={@audit_entries}
            current_scope={@current_scope}
          />
        </div>

        <p :if={@widgets == []} class="mt-5 text-sm text-ink-subtle">
          No widgets are visible for your capabilities.
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

  # Each widget is rendered by its id against the known built-in catalogue.
  # Domain and Extension widgets added through the contribution system are
  # rendered as a placeholder card until their rendering adapters are delivered.
  defp render_widget(%{widget: widget} = assigns) do
    assigns = assign(assigns, :id, widget.id)

    ~H"""
    <%= case @id do %>
      <% "base-dashboard-company-stats" -> %>
        <.company_stat_card
          id="stat-companies"
          count={@company_count}
          navigate={
            if UserAuth.allowed?(@current_scope, "admin.company.list"),
              do: ~p"/companies"
          }
        />
      <% "base-dashboard-user-stats" -> %>
        <.user_stat_card
          id="stat-users"
          count={@user_count}
          navigate={
            if UserAuth.allowed?(@current_scope, "admin.user.list"),
              do: ~p"/users"
          }
        />
      <% "base-dashboard-session-stats" -> %>
        <.session_stat_card
          id="stat-sessions"
          count={@session_count}
          navigate={~p"/system/sessions"}
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
      <% other_id -> %>
        <div
          id={"dashboard-widget-#{other_id}"}
          class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
        >
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
            {@widget.label}
          </p>
        </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :navigate, :string, default: nil

  defp company_stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">Companies</p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
        {@count}
      </p>
      <span class="mt-2 inline-block text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 group-hover:text-ink">
        View all
      </span>
    </.link>
    """
  end

  defp company_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">Companies</p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
        {@count}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :navigate, :string, default: nil

  defp user_stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">Users</p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
        {@count}
      </p>
      <span class="mt-2 inline-block text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 group-hover:text-ink">
        View all
      </span>
    </.link>
    """
  end

  defp user_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">Users</p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
        {@count}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :navigate, :string, default: nil

  defp session_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
        Active Sessions
      </p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
        {@count}
      </p>
      <.link
        :if={@navigate}
        navigate={@navigate}
        class="mt-2 inline-block text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 hover:text-ink"
      >
        View all
      </.link>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :navigate, :string, default: nil

  defp audit_activity_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-xl border border-line bg-surface shadow-xs shadow-ink/[0.03]">
      <div class="flex items-center justify-between border-b border-line px-4 py-3">
        <h3 class="text-sm font-semibold text-ink-strong">Recent Activity</h3>
        <.link
          :if={@navigate}
          navigate={@navigate}
          class="text-xs font-medium text-ink-muted underline decoration-line-strong underline-offset-2 hover:text-ink"
        >
          All activity
        </.link>
      </div>
      <div :if={Enum.empty?(@entries)} class="px-4 py-6 text-center text-sm text-ink-subtle">
        No recent activity.
      </div>
      <div :if={Enum.any?(@entries)} class="divide-y divide-line">
        <div
          :for={entry <- @entries}
          class="flex items-center gap-3 px-4 py-2.5 text-sm"
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
end
