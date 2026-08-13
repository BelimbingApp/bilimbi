defmodule BilimbiWeb.DashboardLive do
  @moduledoc """
  The workspace landing screen after sign-in.

  Scan-first by design (`DESIGN.md`): the workspace identity reads first,
  then the counts a user compares day to day, then the way into each list.
  Every number is a real count from the owning module's public API.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias BilimbiWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok, companies} = Company.list_companies(scope)
    {:ok, users} = User.list_users(scope)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, "dashboard")
     |> assign(:companies, companies)
     |> assign(:users, users)
     |> assign_primary_company(companies)}
  end

  # The tenant's primary company is the workspace's own identity; the dev
  # seed assigns it. Until a public primary-company read exists on the
  # scoped API, the strip falls back to the first listed company and says
  # nothing it cannot prove.
  defp assign_primary_company(socket, companies) do
    current_company_id = socket.assigns.current_scope.user["company_id"]

    current =
      Enum.find(companies, &(&1.id == current_company_id)) || List.first(companies)

    assign(socket, :current_company, current)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Dashboard
          <:subtitle>
            Signed in as {@current_scope.user["name"]} · {@current_scope.scope.tenant.name}
          </:subtitle>
        </.header>

        <div id="dashboard-stats" class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <.stat_card
            id="stat-companies"
            label="Companies"
            count={length(@companies)}
            navigate={if UserAuth.allowed?(@current_scope, "admin.company.list"), do: ~p"/companies"}
          />
          <.stat_card
            id="stat-users"
            label="Users"
            count={length(@users)}
            navigate={if UserAuth.allowed?(@current_scope, "admin.user.list"), do: ~p"/users"}
          />
          <div
            id="stat-tenant"
            class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
          >
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
              Tenant
            </p>
            <p class="mt-1 truncate text-sm font-semibold text-ink-strong">
              {@current_scope.scope.tenant.name}
            </p>
            <div class="mt-1.5 flex items-center gap-2">
              <span class="text-xs tabular-nums text-ink-subtle">#{@current_scope.scope.tenant.id}</span>
              <.badge kind={
                if @current_scope.scope.tenant.status == "active", do: :success, else: :warning
              }>
                {@current_scope.scope.tenant.status}
              </.badge>
            </div>
          </div>
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
          <.table id="dashboard-users" rows={Enum.take(@users, 5)}>
            <:col :let={user} label="Name">
              <span class="font-medium">{user.name}</span>
            </:col>
            <:col :let={user} label="Email">{user.email}</:col>
            <:col :let={user} label="Email verified">
              <.badge kind={if user.email_verified_at, do: :success, else: :warning}>
                {if user.email_verified_at, do: "verified", else: "unverified"}
              </.badge>
            </:col>
          </.table>
          <p
            :if={@users == []}
            class="rounded-xl border border-dashed border-line px-4 py-6 text-center text-sm text-ink-subtle"
          >
            No users are affiliated with a company in this tenant yet.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :navigate, :string, default: nil

  defp stat_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      class="group rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03] transition hover:border-line-strong"
    >
      <.stat_card_body label={@label} count={@count} />
    </.link>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-line bg-surface px-4 py-3.5 shadow-xs shadow-ink/[0.03]"
    >
      <.stat_card_body label={@label} count={@count} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp stat_card_body(assigns) do
    ~H"""
    <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
      {@label}
    </p>
    <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight text-ink-strong">
      {@count}
    </p>
    """
  end
end
