defmodule BilimbiWeb.GeonamesLive.Postcodes do
  @moduledoc """
  Bounded, read-only postcode lookup.

  Postcodes are never listed wholesale: the user supplies both the country and
  postcode, which maps directly to Core Geonames' bounded lookup API.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Geonames

  @impl true
  def mount(_params, _session, socket) do
    countries = Geonames.list_countries()

    {:ok,
     socket
     |> assign(:page_title, "Postcode lookup")
     |> assign(:active_nav, :geonames)
     |> assign(:countries, countries)
     |> assign(:searched?, false)
     |> assign(:postcode_count, 0)
     |> assign_form(%{"country_iso" => "", "postcode" => ""})
     |> stream(:postcodes, [])}
  end

  @impl true
  def handle_event("lookup", %{"postcode_lookup" => attributes}, socket) do
    postcodes =
      Geonames.lookup_postcode(
        Map.get(attributes, "country_iso", ""),
        Map.get(attributes, "postcode", "")
      )

    {:noreply,
     socket
     |> assign(:searched?, true)
     |> assign(:postcode_count, length(postcodes))
     |> assign_form(attributes)
     |> stream(:postcodes, postcodes, reset: true)}
  end

  defp assign_form(socket, attributes) do
    assign(socket, :form, to_form(attributes, as: :postcode_lookup))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Postcode lookup
          <:subtitle>Search imported GeoNames data by country and exact postcode</:subtitle>
        </.header>

        <.alert :if={@countries == []} id="postcode-reference-empty" kind={:info}>
          No country reference data has been imported yet. This is normal on a fresh installation.
        </.alert>

        <.form
          :if={@countries != []}
          for={@form}
          id="postcode-lookup-form"
          phx-submit="lookup"
          class="mt-5 grid max-w-2xl gap-4 rounded-xl border border-line bg-surface px-5 py-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-end"
        >
          <.input
            field={@form[:country_iso]}
            id="postcode-country"
            type="select"
            label="Country"
            prompt="Choose a country"
            options={for country <- @countries, do: {country.country, country.iso}}
          />
          <.input
            field={@form[:postcode]}
            id="postcode-query"
            label="Postcode"
            autocomplete="postal-code"
          />
          <.button id="postcode-search" variant="primary" type="submit" phx-disable-with="Searching…">
            Search
          </.button>
        </.form>

        <.alert
          :if={@searched? && @postcode_count == 0}
          id="postcode-empty"
          kind={:info}
          class="mt-5"
        >
          No postcode matches that country and postcode.
        </.alert>

        <div :if={@postcode_count > 0} class="mt-5">
          <.table id="geonames-postcodes" rows={@streams.postcodes}>
            <:col :let={{_id, postcode}} label="Postcode">
              <code class="text-xs font-medium">{postcode.postcode}</code>
            </:col>
            <:col :let={{_id, postcode}} label="Place">
              <span class="font-medium">{postcode.place_name}</span>
            </:col>
            <:col :let={{_id, postcode}} label="Administrative division">
              {postcode.admin_name1 || postcode.admin1_code || "—"}
            </:col>
            <:col :let={{_id, postcode}} label="Accuracy">
              <span class="tabular-nums">{postcode.accuracy || "—"}</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
