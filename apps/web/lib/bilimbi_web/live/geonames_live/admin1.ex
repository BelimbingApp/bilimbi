defmodule BilimbiWeb.GeonamesLive.Admin1 do
  @moduledoc """
  Read-only first-level administrative-division lookup by country.

  GeoNames records are global reference data. The LiveView keeps only the
  selected country and its streamed lookup result; it never adds a tenant
  scope to the Geonames API.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Geonames

  @impl true
  def mount(_params, _session, socket) do
    countries = Geonames.list_countries()

    {:ok,
     socket
     |> assign(:page_title, "Administrative divisions")
     |> assign(:active_nav, :geonames)
     |> assign(:countries, countries)
     |> assign(:country_selected?, false)
     |> assign(:admin1_count, 0)
     |> assign_form(%{"country_iso" => ""})
     |> stream(:admin1, [])}
  end

  @impl true
  def handle_event("select-country", %{"admin1" => attributes}, socket) do
    country_iso = Map.get(attributes, "country_iso", "")
    admin1 = Geonames.list_admin1(country_iso)

    {:noreply,
     socket
     |> assign(:country_selected?, country_iso != "")
     |> assign(:admin1_count, length(admin1))
     |> assign_form(attributes)
     |> stream(:admin1, admin1, reset: true)}
  end

  defp assign_form(socket, attributes) do
    assign(socket, :form, to_form(attributes, as: :admin1))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Administrative divisions
          <:subtitle>Choose a country to browse its first-level divisions</:subtitle>
        </.header>

        <.alert :if={@countries == []} id="admin1-reference-empty" kind={:info}>
          No country reference data has been imported yet. Import it before browsing divisions.
        </.alert>

        <.form
          :if={@countries != []}
          for={@form}
          id="admin1-country-form"
          phx-change="select-country"
          class="mt-5 max-w-sm rounded-xl border border-line bg-surface px-5 py-4"
        >
          <.input
            field={@form[:country_iso]}
            id="admin1-country"
            type="select"
            label="Country"
            prompt="Choose a country"
            options={for country <- @countries, do: {country.country, country.iso}}
          />
        </.form>

        <.alert
          :if={@country_selected? && @admin1_count == 0}
          id="admin1-empty"
          kind={:info}
          class="mt-5"
        >
          No administrative divisions are available for this country.
        </.alert>

        <div :if={@admin1_count > 0} class="mt-5">
          <.table id="geonames-admin1" rows={@streams.admin1}>
            <:col :let={{_id, admin1}} label="Division">
              <span class="font-medium">{admin1.name}</span>
              <span :if={admin1.alt_name} class="block text-xs text-ink-subtle">
                {admin1.alt_name}
              </span>
            </:col>
            <:col :let={{_id, admin1}} label="Code">
              <code class="text-xs font-medium">{admin1.code}</code>
            </:col>
            <:col :let={{_id, admin1}} label="GeoNames ID">
              <span class="tabular-nums">{admin1.geoname_id || "—"}</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
