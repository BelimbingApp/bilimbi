defmodule Bilimbi.Core.Address.Web.CreateLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Geonames
  alias Ecto.Changeset

  @field_types %{
    label: :string,
    phone: :string,
    line1: :string,
    line2: :string,
    line3: :string,
    country_iso: :string,
    admin1_code: :string,
    postcode: :string,
    locality: :string,
    source: :string,
    source_ref: :string,
    parser_version: :string,
    parse_confidence: :decimal,
    verification_status: :string,
    raw_input: :string
  }
  @verification_statuses ~w(unverified suggested verified)

  @impl true
  def mount(_params, _session, socket) do
    params = %{"source" => "manual", "verification_status" => "unverified"}

    {:ok,
     socket
     |> assign(:page_title, "Create Address")
     |> assign(:active_nav, :addresses)
     |> assign(:countries, Geonames.list_countries())
     |> assign(:form_params, params)
     |> assign(:auto_location, %{admin1_code: false, locality: false})
     |> assign_form(form_changeset(params))
     |> assign_location_options(params)}
  end

  @impl true
  def handle_event("validate", %{"address" => incoming}, socket) do
    {params, auto_location} = location_params(socket, incoming)

    {:noreply,
     socket
     |> assign(:form_params, params)
     |> assign(:auto_location, auto_location)
     |> assign_form(form_changeset(params))
     |> assign_location_options(params)}
  end

  def handle_event("save", %{"address" => incoming}, socket) do
    {params, auto_location} = location_params(socket, incoming)
    changeset = form_changeset(params)

    if changeset.valid? do
      case Address.create_address(socket.assigns.current_scope.scope, params) do
        {:ok, _address} ->
          {:noreply,
           socket
           |> put_flash(:info, "Address created successfully.")
           |> push_navigate(to: ~p"/addresses")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply,
           socket
           |> assign(:form_params, params)
           |> assign(:auto_location, auto_location)
           |> assign_form(copy_domain_errors(changeset, domain_changeset))
           |> assign_location_options(params)}
      end
    else
      {:noreply,
       socket
       |> assign(:form_params, params)
       |> assign(:auto_location, auto_location)
       |> assign_form(changeset)
       |> assign_location_options(params)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div id="address-create-page" class="mx-auto max-w-3xl">
        <.header>
          Create Address
          <:subtitle>Add a tenant-owned address</:subtitle>
          <:actions>
            <.link navigate={~p"/addresses"} class="text-sm font-medium text-ink-muted hover:text-ink">
              Back to Addresses
            </.link>
          </:actions>
        </.header>

        <.form
          for={@form}
          id="address-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-5"
        >
          <section class="rounded-xl border border-line bg-surface px-6 py-5" aria-labelledby="address-contact-heading">
            <h2 id="address-contact-heading" class="mb-4 text-sm font-semibold text-ink">
              Address details
            </h2>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@form[:label]} id="address-label" label="Label" maxlength="255" />
              <.input field={@form[:phone]} id="address-phone" type="tel" label="Phone" maxlength="255" />
            </div>
            <.input field={@form[:line1]} id="address-line1" label="Address line 1" />
            <.input field={@form[:line2]} id="address-line2" label="Address line 2" />
            <.input field={@form[:line3]} id="address-line3" label="Address line 3" />
          </section>

          <section class="rounded-xl border border-line bg-surface px-6 py-5" aria-labelledby="address-location-heading">
            <h2 id="address-location-heading" class="mb-4 text-sm font-semibold text-ink">
              Location
            </h2>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:country_iso]}
                id="address-country"
                type="select"
                label="Country"
                prompt="Choose a country"
                options={country_options(@countries)}
              />
              <div>
                <.input
                  field={@form[:admin1_code]}
                  id="address-admin1"
                  type="select"
                  label="State or province"
                  prompt="Choose a division"
                  options={admin1_options(@admin1_options)}
                  disabled={@admin1_options == []}
                />
                <p :if={@auto_location.admin1_code} id="address-admin1-auto" class="-mt-2 mb-4 text-xs text-ink-subtle">
                  Suggested from postcode
                </p>
              </div>
              <div>
                <.input
                  field={@form[:postcode]}
                  id="address-postcode"
                  label="Postcode"
                  list="address-postcode-options"
                  maxlength="255"
                  disabled={blank?(@form_params["country_iso"])}
                />
                <datalist id="address-postcode-options">
                  <option :for={postcode <- @postcode_options} value={postcode}></option>
                </datalist>
              </div>
              <div>
                <.input
                  field={@form[:locality]}
                  id="address-locality"
                  label="Locality"
                  list="address-locality-options"
                  maxlength="255"
                  disabled={blank?(@form_params["country_iso"])}
                />
                <datalist id="address-locality-options">
                  <option :for={locality <- @locality_options} value={locality}></option>
                </datalist>
                <p :if={@auto_location.locality} id="address-locality-auto" class="-mt-2 mb-4 text-xs text-ink-subtle">
                  Suggested from postcode
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-xl border border-line bg-surface px-6 py-5" aria-labelledby="address-provenance-heading">
            <h2 id="address-provenance-heading" class="mb-4 text-sm font-semibold text-ink">
              Provenance
            </h2>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@form[:source]} id="address-source" label="Source" maxlength="255" />
              <.input field={@form[:source_ref]} id="address-source-ref" label="Source reference" maxlength="255" />
              <.input field={@form[:parser_version]} id="address-parser-version" label="Parser version" maxlength="255" />
              <.input
                field={@form[:parse_confidence]}
                id="address-parse-confidence"
                type="number"
                label="Parse confidence"
                min="0"
                max="1"
                step="0.0001"
              />
              <.input
                field={@form[:verification_status]}
                id="address-verification-status"
                type="select"
                label="Verification status"
                options={verification_status_options()}
                required
              />
            </div>
            <.input field={@form[:raw_input]} id="address-raw-input" type="textarea" label="Raw input" />
          </section>

          <div class="flex items-center gap-4">
            <.button id="address-save" type="submit" variant="primary" phx-disable-with="Creating…">
              Create Address
            </.button>
            <.link navigate={~p"/addresses"} class="text-sm font-medium text-ink-muted hover:text-ink">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp location_params(socket, incoming) do
    old = socket.assigns.form_params
    old_auto = socket.assigns.auto_location
    params = normalize_country(incoming)

    cond do
      field(params, "country_iso") != field(old, "country_iso") ->
        {clear_location_dependents(params), %{admin1_code: false, locality: false}}

      field(params, "postcode") != field(old, "postcode") ->
        apply_postcode(params, old_auto)

      true ->
        {params,
         %{
           admin1_code:
             old_auto.admin1_code and
               field(params, "admin1_code") == field(old, "admin1_code"),
           locality: old_auto.locality and field(params, "locality") == field(old, "locality")
         }}
    end
  end

  defp apply_postcode(params, old_auto) do
    params =
      params
      |> maybe_clear_auto("admin1_code", old_auto.admin1_code)
      |> maybe_clear_auto("locality", old_auto.locality)

    matches =
      Geonames.lookup_postcode(field(params, "country_iso"), field(params, "postcode"))

    localities = matches |> Enum.map(& &1.place_name) |> Enum.reject(&blank?/1) |> Enum.uniq()
    admin1_code = matching_admin1_code(field(params, "country_iso"), matches)

    params = if admin1_code, do: Map.put(params, "admin1_code", admin1_code), else: params

    params =
      if length(localities) == 1, do: Map.put(params, "locality", hd(localities)), else: params

    {params,
     %{
       admin1_code: not is_nil(admin1_code),
       locality: length(localities) == 1
     }}
  end

  defp matching_admin1_code(_country_iso, []), do: nil

  defp matching_admin1_code(country_iso, [first | _rest]) do
    raw_code = first.admin1_code

    country_iso
    |> Geonames.list_admin1()
    |> Enum.find_value(fn admin1 ->
      if admin1.code == raw_code or String.ends_with?(admin1.code, ".#{raw_code}"),
        do: admin1.code
    end)
  end

  defp assign_location_options(socket, params) do
    country_iso = field(params, "country_iso")
    postcode = field(params, "postcode")
    locality = field(params, "locality")
    admin1_code = field(params, "admin1_code")

    exact_localities =
      country_iso
      |> Geonames.lookup_postcode(postcode)
      |> Enum.map(& &1.place_name)
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    locality_options =
      exact_localities ++
        Geonames.search_city_names(country_iso, locality, admin1_code: admin1_code)

    socket
    |> assign(:admin1_options, Geonames.list_admin1(country_iso))
    |> assign(:postcode_options, Geonames.search_postcodes(country_iso, postcode))
    |> assign(:locality_options, Enum.uniq(locality_options))
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:verification_status])
    |> validate_length(:label, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_length(:locality, max: 255)
    |> validate_length(:postcode, max: 255)
    |> validate_length(:country_iso, is: 2)
    |> validate_length(:admin1_code, max: 20)
    |> validate_length(:source, max: 255)
    |> validate_length(:source_ref, max: 255)
    |> validate_length(:parser_version, max: 255)
    |> validate_inclusion(:verification_status, @verification_statuses)
    |> validate_number(:parse_confidence,
      greater_than_or_equal_to: Decimal.new(0),
      less_than_or_equal_to: Decimal.new(1)
    )
    |> Map.put(:action, :validate)
  end

  defp copy_domain_errors(form_changeset, %Changeset{} = domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field), do: add_error(acc, field, message, opts), else: acc
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, %Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset, as: :address))

  defp normalize_country(params) do
    Map.update(params, "country_iso", "", fn value ->
      value |> to_string() |> String.trim() |> String.upcase()
    end)
  end

  defp clear_location_dependents(params) do
    Enum.reduce(~w(admin1_code postcode locality), params, &Map.put(&2, &1, ""))
  end

  defp maybe_clear_auto(params, field_name, true), do: Map.put(params, field_name, "")
  defp maybe_clear_auto(params, _field_name, false), do: params

  defp field(params, name), do: Map.get(params, name, "")

  defp country_options(countries),
    do: Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})

  defp admin1_options(admin1), do: Enum.map(admin1, &{&1.name, &1.code})

  defp verification_status_options do
    Enum.map(@verification_statuses, &{String.capitalize(&1), &1})
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
