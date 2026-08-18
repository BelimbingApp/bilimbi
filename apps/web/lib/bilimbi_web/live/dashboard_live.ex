defmodule BilimbiWeb.DashboardLive do
  @moduledoc """
  The workspace landing screen after sign-in.

  Renders a widget grid whose widget catalogue is contributed by installed
  modules through `Bilimbi.Base.Dashboard`. The catalogue determines which
  widgets appear and in what order; this LiveView owns the rendering.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias BilimbiWeb.UserAuth

  @widget_ids Enum.sort([
               "base-dashboard-company-stats",
               "base-dashboard-user-stats",
               "base-dashboard-session-stats",
               "base-dashboard-recent-audit"
             ])

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok, companies} = Company.list_companies(scope)
    {:ok, users} = User.list_users(scope)

    current_company =
      Enum.find(companies, &(&1.id == socket.assigns.current_scope.user["company_id"])) ||
        List.first(companies)

    catalogue = Dashboard.widgets()
    visible_ids = visible_widget_ids(catalogue, socket)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, nil)
     |> assign(:visible_widget_ids, visible_ids)
     |> assign(:company_count, length(companies))
     |> assign(:user_count, length(users))
     |> assign(:companies, companies)
     |> assign(:users, users)
     |> assign(:current_company, current_company)}
  end

  defp visible_widget_ids(catalogue, socket) do
    catalogue_ids = Enum.map(catalogue, & &1.id)
    scope = socket.assigns.current_scope

    @widget_ids
    |> Enum.filter(fn id ->
      id in catalogue_ids and
        (
          widget = Enum.find(catalogue, &(&1.id == id))
          is_nil(widget.capability) or UserAuth.allowed?(scope, widget.capability)
        )
    end)
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

        <div id="dashboard-widgets" class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <.company_stat_card
            :if={"base-dashboard-company-stats" in @visible_widget_ids}
            id="stat-companies"
            count={@company_count}
            navigate={if UserAuth.allowed?(@current_scope, "admin.company.list"), do: ~p"/companies"}
          />
          <.user_stat_card
            :if={"base-dashboard-user-stats" in @visible_widget_ids}
            id="stat-users"
            count={@user_count}
            navigate={if UserAuth.allowed?(@current_scope, "admin.user.list"), do: ~p"/users"}
          />
          <.session_stat_card
            :if={"base-dashboard-session-stats" in @visible_widget_ids}
            id="stat-sessions"
            navigate={~p"/system/sessions"}
          />
          <.audit_activity_card
            :if={"base-dashboard-recent-audit" in @visible_widget_ids}
            id="stat-recent-audit"
            navigate={~p"/audit/mutations"}
          />
        </div>

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
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">—</p>
    </div>
    """
  end

  attr :id, :string, required: true
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
      <p class="px-4 py-6 text-center text-sm text-ink-subtle">
        Audit log live views are not available yet.
      </p>
    </div>
    """
  end
end
