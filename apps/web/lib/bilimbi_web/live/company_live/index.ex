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
      <div class="mx-auto max-w-4xl">
        <.header>
          Companies
          <:subtitle>Every live company in this tenant</:subtitle>
        </.header>

        <div class="mt-5">
          <.table
            id="companies"
            rows={@streams.companies}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, company} -> company end}
            caption="Companies"
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
              <.link navigate={~p"/companies/#{company.id}"} class="text-xs font-medium">
                Open
              </.link>
            </:action>
            <:empty :if={@companies_count == 0}>
              No companies found in this workspace.
            </:empty>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
