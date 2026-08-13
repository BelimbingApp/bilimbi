defmodule BilimbiWeb.GeonamesLive.Countries do
  @moduledoc """
  Read-only GeoNames country reference list.

  A fresh installation has no imported reference data, so an empty list is a
  normal operational state rather than an application error.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Geonames

  @impl true
  def mount(_params, _session, socket) do
    countries = Geonames.list_countries()

    {:ok,
     socket
     |> assign(:page_title, "Countries")
     |> assign(:active_nav, :geonames)
     |> assign(:country_count, length(countries))
     |> stream(:countries, countries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Countries
          <:subtitle>GeoNames reference data available to every workspace</:subtitle>
        </.header>

        <.alert :if={@country_count == 0} id="countries-empty" kind={:info}>
          No country reference data has been imported yet. This is normal on a fresh installation.
        </.alert>

        <div :if={@country_count > 0} class="mt-5">
          <.table id="geonames-countries" rows={@streams.countries}>
            <:col :let={{_id, country}} label="Country">
              <span class="font-medium">{country.country}</span>
            </:col>
            <:col :let={{_id, country}} label="ISO">
              <code class="text-xs font-medium">{country.iso}</code>
            </:col>
            <:col :let={{_id, country}} label="Capital">
              {country.capital || "—"}
            </:col>
            <:col :let={{_id, country}} label="Population">
              <span class="tabular-nums">{country.population}</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
