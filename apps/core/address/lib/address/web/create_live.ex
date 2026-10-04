defmodule Bilimbi.Core.Address.Web.CreateLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.UI.FormErrors
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.LocationSuggestion
  alias Bilimbi.Core.Address.Web.LocationFields
  alias Bilimbi.Core.Geonames
  alias Ecto.Changeset

  import LocationFields

  @location_ids %{
    country: "address-country",
    admin1: "address-admin1",
    postcode: "address-postcode",
    locality: "address-locality",
    postcode_list: "address-postcode-options",
    locality_list: "address-locality-options",
    admin1_auto: "address-admin1-auto",
    locality_auto: "address-locality-auto"
  }

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
     |> assign(:location_ids, @location_ids)
     |> assign(:page_title, "Create Address")
     |> assign(:active_nav, "admin.address")
     |> assign(:country_options, Geonames.country_options())
     |> assign(:form_params, params)
     |> assign(:auto_location, %{admin1_code: false, locality: false})
     |> assign_form(form_changeset(params))
     |> assign_location_options(params)}
  end

  @impl true
  def handle_event("validate", %{"address" => incoming}, socket) do
    {params, auto_location} =
      LocationSuggestion.suggest(
        incoming,
        socket.assigns.form_params,
        socket.assigns.auto_location
      )

    {:noreply,
     socket
     |> assign(:form_params, params)
     |> assign(:auto_location, auto_location)
     |> assign_form(form_changeset(params))
     |> assign_location_options(params)}
  end

  def handle_event("save", %{"address" => incoming}, socket) do
    {params, auto_location} =
      LocationSuggestion.suggest(
        incoming,
        socket.assigns.form_params,
        socket.assigns.auto_location
      )

    changeset = form_changeset(params)

    if changeset.valid? do
      case Address.create_address(socket.assigns.current_scope.scope, params) do
        {:ok, _address} ->
          {:noreply,
           socket
           |> put_flash(:success, "Address created successfully.")
           |> push_navigate(to: ~p"/addresses")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply,
           socket
           |> assign(:form_params, params)
           |> assign(:auto_location, auto_location)
           |> assign_form(
             FormErrors.copy(changeset, domain_changeset, only: @field_types, action: :insert)
           )
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
      <.page id="address-create-page" variant={:form}>
        <.header>
          Create Address
          <:subtitle>Add a tenant-owned address</:subtitle>
          <:actions>
            <.back_link id="address-back" navigate={~p"/addresses"} title="Back to addresses" />
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
            <.location_fields
              form={@form}
              ids={@location_ids}
              country_options={@country_options}
              admin1_options={@admin1_options}
              postcode_options={@postcode_options}
              locality_options={@locality_options}
              auto={@auto_location}
              country_blank?={blank?(@form_params["country_iso"])}
            />
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
            <.link id="address-cancel" navigate={~p"/addresses"} class="text-sm font-medium text-ink-muted hover:text-ink">
              Cancel
            </.link>
          </div>
        </.form>
      </.page>
    </Layouts.app>
    """
  end

  defp assign_location_options(socket, params) do
    options = LocationSuggestion.options(params)

    socket
    |> assign(:admin1_options, options.admin1)
    |> assign(:postcode_options, options.postcodes)
    |> assign(:locality_options, options.localities)
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

  defp assign_form(socket, %Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset, as: :address))

  defp verification_status_options do
    Enum.map(@verification_statuses, &{String.capitalize(&1), &1})
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
