defmodule BilimbiWeb.CompanyLive.Index do
  @moduledoc "Tenant-wide company list, via `Bilimbi.Core.Company.list_companies/1`."

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, companies} = Company.list_companies(scope)

    {:ok,
     socket
     |> assign(:page_title, "Companies")
     |> assign(:active_nav, "admin.company")
     |> assign(:companies_count, length(companies))
     |> stream(:companies, companies)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="companies-index">
        <.header>
          Companies
          <:title_actions>
            <button
              type="button"
              id="companies-pin"
              data-nav-pin="nav-admin-company"
              title="Pin Companies to sidebar"
              aria-label="Pin Companies to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>Every live company in this tenant</:subtitle>
        </.header>

        <.card id="companies-card" inner_class="p-0">
          <.table
            id="companies"
            rows={@streams.companies}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, company} -> company end}
            caption="Companies"
            framed={false}
          >
            <:col :let={company} label="Name">
              <.link
                navigate={~p"/companies/#{company.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {Company.Summary.display_name(company)}
              </.link>
              <span
                :if={company.legal_name && company.legal_name != company.name}
                class="block text-xs text-ink-subtle"
              >
                {company.name}
              </span>
            </:col>
            <:col :let={company} label="Code">
              <code class="text-xs font-medium">{company.code}</code>
            </:col>
            <:col :let={company} label="Status">
              <.badge kind={if company.status == "active", do: :success, else: :warning}>
                {company.status}
              </.badge>
            </:col>
            <:action :let={company}>
              <.link
                navigate={~p"/companies/#{company.id}"}
                class="text-xs font-medium text-action hover:underline"
              >
                Open
              </.link>
            </:action>
            <:empty :if={@companies_count == 0}>
              No companies found in this workspace.
            </:empty>
          </.table>
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
