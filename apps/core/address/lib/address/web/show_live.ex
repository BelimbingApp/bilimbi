defmodule Bilimbi.Core.Address.Web.ShowLive do
  @moduledoc """
  LiveView adapter for displaying and managing a tenant-owned address.

  Presents address attributes, location normalization, provenance metadata, and
  polymorphically linked owner entities (Companies, Employees).

  In strict alignment with Belimbing's `admin/addresses/show` screen, this view
  surfaces:
  - Address details editing (label, phone, verification status, street lines);
  - Geographic location editing with live GeoNames country, division, postcode,
    and locality autocompletion;
  - Provenance audit editing (source, source reference, parser metadata, raw input);
  - Live linked entities table with multi-column sorting (`type`, `name`, `kind`,
    `is_primary`, `priority`, `valid_from`, `valid_to`);
  - Contextual navigation back to an owning Company when `?company=ID` is present.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.UI.Layouts
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.Detail
  alias Bilimbi.Core.Geonames

  @sortable_linked_fields ~w(type name kind is_primary priority valid_from valid_to)a
  @verification_statuses ~w(unverified suggested verified)

  @impl true
  def mount(%{"id" => id_param} = params, _session, socket) do
    current_scope = socket.assigns.current_scope
    scope = current_scope.scope

    if allowed?(current_scope, "admin.address.view") do
      with {:ok, address_id} <- parse_id(id_param),
           {:ok, address} <- Address.get_address_detail(scope, address_id) do
        company_context_id = resolve_company_context(scope, address, params["company"])
        countries = Geonames.list_countries()

        {:ok,
         socket
         |> assign(:page_title, address.label || "Address ##{address.id}")
         |> assign(:active_nav, :addresses)
         |> assign(:address_id, address_id)
         |> assign(:address, address)
         |> assign(:company_context_id, company_context_id)
         |> assign(:countries, countries)
         |> assign(:linked_sort_by, :type)
         |> assign(:linked_sort_dir, :asc)
         |> assign(:editing_details?, false)
         |> assign(:editing_location?, false)
         |> assign(:editing_provenance?, false)
         |> assign_details_form(address)
         |> assign_location_form(address)
         |> assign_provenance_form(address)}
      else
        _ ->
          {:ok,
           socket
           |> put_flash(:error, "Address not found.")
           |> push_navigate(to: ~p"/addresses")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view this address.")
       |> push_navigate(to: ~p"/addresses")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns[:address] do
      sort_by = parse_sort_by(params["linked_sort_by"])
      sort_dir = parse_sort_dir(params["linked_sort_dir"])

      scope = socket.assigns.current_scope.scope
      address_id = socket.assigns.address_id

      case Address.get_address_detail(scope, address_id,
             owner_sort_by: sort_by,
             owner_sort_dir: sort_dir
           ) do
        {:ok, address} ->
          {:noreply,
           socket
           |> assign(:address, address)
           |> assign(:linked_sort_by, sort_by)
           |> assign(:linked_sort_dir, sort_dir)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ============================================================================
  # Event Handlers: Details Card
  # ============================================================================

  @impl true
  def handle_event("edit_details", _params, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      {:noreply,
       socket
       |> assign(:editing_details?, true)
       |> assign_details_form(socket.assigns.address)}
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  def handle_event("cancel_edit_details", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_details?, false)
     |> assign_details_form(socket.assigns.address)}
  end

  def handle_event("validate_details", %{"details" => params}, socket) do
    form =
      params
      |> sanitize_details_params()
      |> to_form(as: :details)

    {:noreply, assign(socket, :details_form, form)}
  end

  def handle_event("save_details", %{"details" => params}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      scope = socket.assigns.current_scope.scope
      attrs = sanitize_details_params(params)

      case Address.update_address(scope, socket.assigns.address_id, attrs) do
        {:ok, _summary} ->
          {:ok, refreshed} =
            Address.get_address_detail(scope, socket.assigns.address_id,
              owner_sort_by: socket.assigns.linked_sort_by,
              owner_sort_dir: socket.assigns.linked_sort_dir
            )

          {:noreply,
           socket
           |> put_flash(:info, "Address details updated successfully.")
           |> assign(:address, refreshed)
           |> assign(:page_title, refreshed.label || "Address ##{refreshed.id}")
           |> assign(:editing_details?, false)
           |> assign_details_form(refreshed)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:details_form, to_form(changeset, as: :details))
           |> put_flash(:error, "Could not update address details.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update address: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  # ============================================================================
  # Event Handlers: Location Card
  # ============================================================================

  def handle_event("edit_location", _params, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      {:noreply,
       socket
       |> assign(:editing_location?, true)
       |> assign_location_form(socket.assigns.address)}
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  def handle_event("cancel_edit_location", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_location?, false)
     |> assign_location_form(socket.assigns.address)}
  end

  def handle_event("validate_location", %{"location" => params}, socket) do
    country_iso = normalize_param(params["country_iso"])
    postcode = normalize_param(params["postcode"])
    locality = normalize_param(params["locality"])
    admin1_code = normalize_param(params["admin1_code"])

    admin1_options =
      if country_iso, do: Geonames.list_admin1(country_iso), else: []

    postcode_options =
      if country_iso && postcode && String.length(postcode) >= 2 do
        Geonames.search_postcodes(country_iso, postcode)
      else
        []
      end

    matches =
      if country_iso && postcode do
        Geonames.lookup_postcode(country_iso, postcode)
      else
        []
      end

    localities = matches |> Enum.map(& &1.place_name) |> Enum.reject(&blank?/1) |> Enum.uniq()
    auto_admin1 = matching_admin1_code(country_iso, matches)
    auto_locality = if length(localities) == 1, do: hd(localities), else: nil

    locality_options =
      if country_iso && locality && String.length(locality) >= 2 do
        Enum.uniq(localities ++ Geonames.search_city_names(country_iso, locality))
      else
        localities
      end

    effective_admin1 =
      cond do
        admin1_code != nil and admin1_code != "" -> admin1_code
        auto_admin1 != nil -> auto_admin1
        true -> nil
      end

    effective_locality =
      cond do
        locality != nil and locality != "" -> locality
        auto_locality != nil -> auto_locality
        true -> locality
      end

    merged_params = %{
      "country_iso" => country_iso || "",
      "admin1_code" => effective_admin1 || "",
      "postcode" => postcode || "",
      "locality" => effective_locality || ""
    }

    {:noreply,
     socket
     |> assign(:admin1_options, admin1_options)
     |> assign(:postcode_options, postcode_options)
     |> assign(:locality_options, locality_options)
     |> assign(:auto_location, %{admin1_code: auto_admin1, locality: auto_locality})
     |> assign(:location_params, merged_params)
     |> assign(:location_form, to_form(merged_params, as: :location))}
  end

  def handle_event("save_location", %{"location" => params}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      scope = socket.assigns.current_scope.scope

      attrs = %{
        "country_iso" => normalize_param(params["country_iso"]),
        "admin1_code" => normalize_param(params["admin1_code"]),
        "postcode" => normalize_param(params["postcode"]),
        "locality" => normalize_param(params["locality"])
      }

      case Address.update_address(scope, socket.assigns.address_id, attrs) do
        {:ok, _summary} ->
          {:ok, refreshed} =
            Address.get_address_detail(scope, socket.assigns.address_id,
              owner_sort_by: socket.assigns.linked_sort_by,
              owner_sort_dir: socket.assigns.linked_sort_dir
            )

          {:noreply,
           socket
           |> put_flash(:info, "Address location updated successfully.")
           |> assign(:address, refreshed)
           |> assign(:editing_location?, false)
           |> assign_location_form(refreshed)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:location_form, to_form(changeset, as: :location))
           |> put_flash(:error, "Could not update address location.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update location: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  # ============================================================================
  # Event Handlers: Provenance Card
  # ============================================================================

  def handle_event("edit_provenance", _params, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      {:noreply,
       socket
       |> assign(:editing_provenance?, true)
       |> assign_provenance_form(socket.assigns.address)}
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  def handle_event("cancel_edit_provenance", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_provenance?, false)
     |> assign_provenance_form(socket.assigns.address)}
  end

  def handle_event("validate_provenance", %{"provenance" => params}, socket) do
    form =
      params
      |> sanitize_provenance_params()
      |> to_form(as: :provenance)

    {:noreply, assign(socket, :provenance_form, form)}
  end

  def handle_event("save_provenance", %{"provenance" => params}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.update") do
      scope = socket.assigns.current_scope.scope
      attrs = sanitize_provenance_params(params)

      case Address.update_address(scope, socket.assigns.address_id, attrs) do
        {:ok, _summary} ->
          {:ok, refreshed} =
            Address.get_address_detail(scope, socket.assigns.address_id,
              owner_sort_by: socket.assigns.linked_sort_by,
              owner_sort_dir: socket.assigns.linked_sort_dir
            )

          {:noreply,
           socket
           |> put_flash(:info, "Provenance updated successfully.")
           |> assign(:address, refreshed)
           |> assign(:editing_provenance?, false)
           |> assign_provenance_form(refreshed)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:provenance_form, to_form(changeset, as: :provenance))
           |> put_flash(:error, "Could not update provenance.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update provenance: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to update addresses.")}
    end
  end

  # ============================================================================
  # Event Handlers: Linked Entities Sorting
  # ============================================================================

  def handle_event("sort", %{"sort" => sort_by_param}, socket) do
    sort_by = parse_sort_by(sort_by_param)
    current_sort_by = socket.assigns.linked_sort_by
    current_sort_dir = socket.assigns.linked_sort_dir

    new_dir =
      if sort_by == current_sort_by do
        if current_sort_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    company_param =
      if socket.assigns.company_context_id do
        %{company: socket.assigns.company_context_id}
      else
        %{}
      end

    query =
      company_param
      |> Map.put(:linked_sort_by, Atom.to_string(sort_by))
      |> Map.put(:linked_sort_dir, Atom.to_string(new_dir))

    {:noreply, push_patch(socket, to: ~p"/addresses/#{socket.assigns.address_id}?#{query}")}
  end

  # ============================================================================
  # Template Rendering
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="address-show-page">
        <.header>
          Address Details
          <:subtitle>{@address.label || "Address ##{@address.id}"}</:subtitle>
          <:actions>
            <.button
              :if={@company_context_id}
              id="address-back-company"
              navigate={~p"/companies/#{@company_context_id}"}
            >
              <.icon name="hero-arrow-left" class="mr-1.5 size-4" /> Back to Company
            </.button>
            <.button id="address-back-list" navigate={~p"/addresses"}>
              <.icon name="hero-arrow-left" class="mr-1.5 size-4" /> Back to List
            </.button>
          </:actions>
        </.header>

        <div class="space-y-6">
          <!-- CARD 1: Address Details -->
          <section
            id="address-details-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-details-heading"
          >
            <div class="mb-4 flex items-center justify-between">
              <h2
                id="address-details-heading"
                class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
              >
                Address Details
              </h2>
              <div :if={allowed?(@current_scope, "admin.address.update")}>
                <.button
                  :if={not @editing_details?}
                  id="address-edit-details-button"
                  type="button"
                  phx-click="edit_details"
                >
                  <.icon name="hero-pencil-square" class="mr-1 size-3.5" /> Edit Details
                </.button>
              </div>
            </div>

            <!-- Details Form (Edit Mode) -->
            <div :if={@editing_details?}>
              <.form
                for={@details_form}
                id="address-details-form"
                phx-change="validate_details"
                phx-submit="save_details"
                class="space-y-4"
              >
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@details_form[:label]}
                    id="address-details-label"
                    label="Label"
                    maxlength="255"
                  />
                  <.input
                    field={@details_form[:phone]}
                    id="address-details-phone"
                    type="tel"
                    label="Phone"
                    maxlength="255"
                  />
                </div>

                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@details_form[:verification_status]}
                    id="address-details-verification-status"
                    type="select"
                    label="Verification Status"
                    options={verification_status_options()}
                  />
                </div>

                <div class="grid gap-x-4 sm:grid-cols-3">
                  <.input field={@details_form[:line1]} id="address-details-line1" label="Address Line 1" />
                  <.input field={@details_form[:line2]} id="address-details-line2" label="Address Line 2" />
                  <.input field={@details_form[:line3]} id="address-details-line3" label="Address Line 3" />
                </div>

                <div class="flex items-center gap-3 pt-2">
                  <.button id="address-save-details" type="submit" variant="primary">
                    Save Details
                  </.button>
                  <.button
                    id="address-cancel-details"
                    type="button"
                    phx-click="cancel_edit_details"
                  >
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>

            <!-- Details View (Read Mode) -->
            <div :if={not @editing_details?}>
              <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3">
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">Label</dt>
                  <dd id="address-view-label" class="mt-1 text-sm font-medium text-ink">
                    {@address.label || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">Phone</dt>
                  <dd id="address-view-phone" class="mt-1 text-sm text-ink">
                    {@address.phone || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Verification Status
                  </dt>
                  <dd id="address-view-verification-status" class="mt-1 text-sm">
                    <.badge kind={verification_badge_kind(@address.verification_status)}>
                      {String.capitalize(@address.verification_status || "unverified")}
                    </.badge>
                  </dd>
                </div>
                <div class="sm:col-span-2 md:col-span-3">
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Street Address
                  </dt>
                  <dd id="address-view-lines" class="mt-1 space-y-0.5 text-sm text-ink">
                    <p :if={@address.line1}>{@address.line1}</p>
                    <p :if={@address.line2}>{@address.line2}</p>
                    <p :if={@address.line3}>{@address.line3}</p>
                    <p :if={is_nil(@address.line1) and is_nil(@address.line2) and is_nil(@address.line3)} class="text-ink-muted">
                      —
                    </p>
                  </dd>
                </div>
              </dl>
            </div>
          </section>

          <!-- CARD 2: Geographic Location -->
          <section
            id="address-location-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-location-heading"
          >
            <div class="mb-4 flex items-center justify-between">
              <div>
                <h2
                  id="address-location-heading"
                  class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                >
                  Geographic Location
                </h2>
                <p class="mt-0.5 text-xs text-ink-subtle">
                  Linked to GeoNames reference database for standardization and lookup.
                </p>
              </div>

              <div :if={allowed?(@current_scope, "admin.address.update")}>
                <.button
                  :if={not @editing_location?}
                  id="address-edit-location-button"
                  type="button"
                  phx-click="edit_location"
                >
                  <.icon name="hero-pencil-square" class="mr-1 size-3.5" /> Edit Location
                </.button>
              </div>
            </div>

            <!-- Location Form (Edit Mode) -->
            <div :if={@editing_location?} class="mt-4 border-t border-line pt-4">
              <.form
                for={@location_form}
                id="address-location-form"
                phx-change="validate_location"
                phx-submit="save_location"
                class="space-y-4"
              >
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@location_form[:country_iso]}
                    id="address-location-country"
                    type="select"
                    label="Country"
                    prompt="Choose a country"
                    options={country_options(@countries)}
                  />
                  <div>
                    <.input
                      field={@location_form[:admin1_code]}
                      id="address-location-admin1"
                      type="select"
                      label="State or Province"
                      prompt="Choose a division"
                      options={admin1_options(@admin1_options)}
                      disabled={@admin1_options == []}
                    />
                    <p
                      :if={@auto_location.admin1_code}
                      id="address-location-admin1-auto"
                      class="-mt-2 mb-3 text-xs text-ink-subtle"
                    >
                      Suggested from postcode
                    </p>
                  </div>
                </div>

                <div class="grid gap-x-4 sm:grid-cols-2">
                  <div>
                    <.input
                      field={@location_form[:postcode]}
                      id="address-location-postcode"
                      label="Postal Code"
                      list="address-location-postcode-options"
                      maxlength="255"
                      disabled={blank?(@location_params["country_iso"])}
                    />
                    <datalist id="address-location-postcode-options">
                      <option :for={postcode <- @postcode_options} value={postcode}></option>
                    </datalist>
                  </div>
                  <div>
                    <.input
                      field={@location_form[:locality]}
                      id="address-location-locality"
                      label="Locality / City"
                      list="address-location-locality-options"
                      maxlength="255"
                      disabled={blank?(@location_params["country_iso"])}
                    />
                    <datalist id="address-location-locality-options">
                      <option :for={locality <- @locality_options} value={locality}></option>
                    </datalist>
                    <p
                      :if={@auto_location.locality}
                      id="address-location-locality-auto"
                      class="-mt-2 mb-3 text-xs text-ink-subtle"
                    >
                      Suggested from postcode
                    </p>
                  </div>
                </div>

                <div class="flex items-center gap-3 pt-2">
                  <.button id="address-save-location" type="submit" variant="primary">
                    Apply Location
                  </.button>
                  <.button
                    id="address-cancel-location"
                    type="button"
                    phx-click="cancel_edit_location"
                  >
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>

            <!-- Location View (Read Mode) -->
            <div :if={not @editing_location?} class="mt-4 border-t border-line pt-4">
              <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-4">
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Country
                  </dt>
                  <dd id="address-view-country" class="mt-1 text-sm text-ink">
                    {@address.country_name || @address.country_iso || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    State / Province
                  </dt>
                  <dd id="address-view-admin1" class="mt-1 text-sm text-ink">
                    {@address.admin1_name || @address.admin1_code || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Postal Code
                  </dt>
                  <dd id="address-view-postcode" class="mt-1 text-sm tabular-nums text-ink">
                    {@address.postcode || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Locality
                  </dt>
                  <dd id="address-view-locality" class="mt-1 text-sm text-ink">
                    {@address.locality || "—"}
                  </dd>
                </div>
              </dl>
            </div>
          </section>

          <!-- CARD 3: Provenance -->
          <section
            id="address-provenance-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-provenance-heading"
          >
            <div class="mb-4 flex items-start justify-between">
              <div>
                <h2
                  id="address-provenance-heading"
                  class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                >
                  Provenance
                </h2>
                <p class="mt-0.5 text-xs text-ink-subtle">
                  Tracks where this address came from and how it was processed — useful for auditing data quality and imports.
                </p>
              </div>

              <div :if={allowed?(@current_scope, "admin.address.update")}>
                <.button
                  :if={not @editing_provenance?}
                  id="address-edit-provenance-button"
                  type="button"
                  phx-click="edit_provenance"
                >
                  <.icon name="hero-pencil-square" class="mr-1 size-3.5" /> Edit Provenance
                </.button>
              </div>
            </div>

            <!-- Provenance Form (Edit Mode) -->
            <div :if={@editing_provenance?}>
              <.form
                for={@provenance_form}
                id="address-provenance-form"
                phx-change="validate_provenance"
                phx-submit="save_provenance"
                class="space-y-4"
              >
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@provenance_form[:source]}
                    id="address-provenance-source"
                    label="Source"
                    maxlength="255"
                  />
                  <.input
                    field={@provenance_form[:source_ref]}
                    id="address-provenance-source-ref"
                    label="Source Reference"
                    maxlength="255"
                  />
                </div>

                <div class="flex items-center gap-3 pt-2">
                  <.button id="address-save-provenance" type="submit" variant="primary">
                    Save Provenance
                  </.button>
                  <.button
                    id="address-cancel-provenance"
                    type="button"
                    phx-click="cancel_edit_provenance"
                  >
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>

            <!-- Provenance View (Read Mode) -->
            <div :if={not @editing_provenance?}>
              <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-4">
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">Source</dt>
                  <dd id="address-view-source" class="mt-1 text-sm text-ink">
                    {@address.source || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Source Reference
                  </dt>
                  <dd id="address-view-source-ref" class="mt-1 text-sm text-ink">
                    {@address.source_ref || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Parser Version
                  </dt>
                  <dd id="address-view-parser-version" class="mt-1 text-sm text-ink">
                    {@address.parser_version || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Parse Confidence
                  </dt>
                  <dd id="address-view-parse-confidence" class="mt-1 text-sm tabular-nums text-ink">
                    {@address.parse_confidence || "—"}
                  </dd>
                </div>
                <div :if={@address.raw_input} class="sm:col-span-2 md:col-span-4 mt-2 border-t border-line pt-4">
                  <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                    Raw Input
                  </dt>
                  <dd class="mt-1">
                    <pre
                      id="address-view-raw-input"
                      class="overflow-x-auto rounded-xl border border-line bg-surface-subtle p-3 font-mono text-xs text-ink"
                    >{@address.raw_input}</pre>
                  </dd>
                </div>
              </dl>
            </div>
          </section>

          <!-- CARD 4: Linked Entities -->
          <section
            id="address-linked-entities-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-linked-entities-heading"
          >
            <div class="mb-4">
              <h2
                id="address-linked-entities-heading"
                class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
              >
                Linked Entities
              </h2>
              <p class="mt-0.5 text-xs text-ink-subtle">
                Companies, employees, or other records that use this address. One address can be shared by multiple entities with different roles (e.g., billing, shipping).
              </p>
            </div>

            <div class="overflow-x-auto">
              <.table
                id="address-linked-entities-table"
                rows={@address.linked_owners}
                sort_by={@linked_sort_by}
                sort_dir={@linked_sort_dir}
                framed={false}
              >
                <:col :let={owner} label="Entity Type" sort="type" sort_id="sort-type">
                  <span class="whitespace-nowrap font-medium text-ink">
                    {format_owner_type(owner.owner_type)}
                  </span>
                </:col>

                <:col :let={owner} label="Name" sort="name" sort_id="sort-name">
                  <span class="whitespace-nowrap font-medium">
                    <%= if owner.owner_type == :company do %>
                      <.link
                        navigate={~p"/companies/#{owner.owner_id}"}
                        id={"linked-company-#{owner.owner_id}"}
                        class="text-action hover:underline"
                      >
                        {owner.name}
                      </.link>
                    <% else %>
                      <%= if owner.owner_type == :employee do %>
                        <.link
                          navigate={~p"/employees/#{owner.owner_id}"}
                          id={"linked-employee-#{owner.owner_id}"}
                          class="text-action hover:underline"
                        >
                          {owner.name}
                        </.link>
                      <% else %>
                        <span>{owner.name}</span>
                      <% end %>
                    <% end %>
                  </span>
                </:col>

                <:col :let={owner} label="Kind" sort="kind" sort_id="sort-kind">
                  <div class="flex flex-wrap gap-1">
                    <%= if owner.kind != [] do %>
                      <.badge :for={kind <- owner.kind} kind={:neutral}>
                        {String.capitalize(kind)}
                      </.badge>
                    <% else %>
                      <span class="text-ink-muted">—</span>
                    <% end %>
                  </div>
                </:col>

                <:col :let={owner} label="Primary" sort="is_primary" sort_id="sort-is-primary">
                  <span class="whitespace-nowrap text-sm text-ink-muted">
                    {if owner.is_primary, do: "Yes", else: "No"}
                  </span>
                </:col>

                <:col :let={owner} label="Priority" sort="priority" sort_id="sort-priority">
                  <span class="whitespace-nowrap tabular-nums text-sm text-ink-muted">
                    {owner.priority || "—"}
                  </span>
                </:col>

                <:col :let={owner} label="Valid From" sort="valid_from" sort_id="sort-valid-from">
                  <span class="whitespace-nowrap tabular-nums text-sm text-ink-muted">
                    {owner.valid_from || "—"}
                  </span>
                </:col>

                <:col :let={owner} label="Valid To" sort="valid_to" sort_id="sort-valid-to">
                  <span class="whitespace-nowrap tabular-nums text-sm text-ink-muted">
                    {owner.valid_to || "—"}
                  </span>
                </:col>

                <:empty :if={@address.linked_owners == []}>
                  No linked entities.
                </:empty>
              </.table>
            </div>
          </section>
        </div>
      </.page>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp parse_sort_by(nil), do: :type

  defp parse_sort_by(val) when is_binary(val) do
    case String.to_existing_atom(val) do
      col when col in @sortable_linked_fields -> col
      _ -> :type
    end
  rescue
    ArgumentError -> :type
  end

  defp parse_sort_by(val) when val in @sortable_linked_fields, do: val
  defp parse_sort_by(_), do: :type

  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(:desc), do: :desc
  defp parse_sort_dir(_), do: :asc

  defp resolve_company_context(scope, %Detail{linked_owners: owners}, company_id_param)
       when is_binary(company_id_param) do
    with {company_id, ""} when company_id > 0 <- Integer.parse(company_id_param),
         true <-
           Enum.any?(
             owners,
             &(&1.owner_type == :company and &1.owner_id == company_id)
           ),
         {:ok, _company} <- Bilimbi.Core.Company.get_company(scope, company_id) do
      company_id
    else
      _ -> nil
    end
  end

  defp resolve_company_context(_scope, _address, _param), do: nil

  defp assign_details_form(socket, %Detail{} = address) do
    data = %{
      "label" => address.label || "",
      "phone" => address.phone || "",
      "verification_status" => address.verification_status || "unverified",
      "line1" => address.line1 || "",
      "line2" => address.line2 || "",
      "line3" => address.line3 || ""
    }

    assign(socket, :details_form, to_form(data, as: :details))
  end

  defp assign_location_form(socket, %Detail{} = address) do
    country_iso = address.country_iso || ""
    admin1_options = if country_iso != "", do: Geonames.list_admin1(country_iso), else: []

    data = %{
      "country_iso" => country_iso,
      "admin1_code" => address.admin1_code || "",
      "postcode" => address.postcode || "",
      "locality" => address.locality || ""
    }

    socket
    |> assign(:admin1_options, admin1_options)
    |> assign(:postcode_options, [])
    |> assign(:locality_options, [])
    |> assign(:auto_location, %{admin1_code: nil, locality: nil})
    |> assign(:location_params, data)
    |> assign(:location_form, to_form(data, as: :location))
  end

  defp assign_provenance_form(socket, %Detail{} = address) do
    data = %{
      "source" => address.source || "",
      "source_ref" => address.source_ref || ""
    }

    assign(socket, :provenance_form, to_form(data, as: :provenance))
  end

  defp sanitize_details_params(params) do
    %{
      "label" => normalize_param(params["label"]),
      "phone" => normalize_param(params["phone"]),
      "verification_status" => normalize_param(params["verification_status"]) || "unverified",
      "line1" => normalize_param(params["line1"]),
      "line2" => normalize_param(params["line2"]),
      "line3" => normalize_param(params["line3"])
    }
  end

  defp sanitize_provenance_params(params) do
    %{
      "source" => normalize_param(params["source"]),
      "source_ref" => normalize_param(params["source_ref"])
    }
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

  defp normalize_param(nil), do: nil

  defp normalize_param(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_param(other), do: other

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp verification_status_options do
    Enum.map(@verification_statuses, &{String.capitalize(&1), &1})
  end

  defp verification_badge_kind("verified"), do: :success
  defp verification_badge_kind("suggested"), do: :warning
  defp verification_badge_kind(_), do: :neutral

  defp format_owner_type(:company), do: "Company"
  defp format_owner_type(:employee), do: "Employee"
  defp format_owner_type(other), do: other |> to_string() |> String.capitalize()

  defp country_options(countries) do
    Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})
  end

  defp admin1_options(admin1s) do
    Enum.map(admin1s, &{&1.name, &1.code})
  end
end
