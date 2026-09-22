defmodule Bilimbi.Core.Address.Web.ShowLive do
  @moduledoc """
  Read-first LiveView adapter for one tenant-owned address.

  The page shows the address as facts. An operator holding
  `admin.address.update` edits each fact in place and a committed edit saves
  by itself; there is no edit mode and no save button. What "committed" means
  follows the control, and is the same for every fact of that kind:

  - a text fact (label, phone, street lines, source, source reference) commits
    on Enter or on leaving the field, through `<.inline_edit>`; Escape cancels;
  - a choice fact (verification status) commits on change, and Escape or
    leaving the select cancels;
  - the location facts (country, division, postcode, locality) depend on one
    another — a country change invalidates the other three — so they commit
    together through one grouped editor with Apply and Cancel, as Belimbing's
    `admin/addresses/show` does.

  Each fact reports its own outcome: "Saving…" while the round trip is in
  flight, "Saved" once stored, and an alert on the fact naming the rejected
  value and the validation error when the save was refused. The stored value
  stays on screen until the server confirms a change.

  The header carries the record history as a demoted labelled action — the
  registry's `history` clock beside the visible word "History", in the same
  link treatment as the back links — and plain "← Back" links: to the owning Company when `?company=ID` names a linked
  Company, and to the address list.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.Layouts
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.Detail
  alias Bilimbi.Core.Geonames

  @sortable_linked_fields ~w(type name kind is_primary priority valid_from valid_to)a
  @verification_statuses ~w(unverified suggested verified)

  # The facts an inline text edit may write, keyed by the form name the hook
  # pushes. A name outside this map is ignored; user input never becomes an atom.
  @inline_fields %{
    "label" => :label,
    "phone" => :phone,
    "line1" => :line1,
    "line2" => :line2,
    "line3" => :line3,
    "source" => :source,
    "source_ref" => :source_ref
  }

  @fact_labels %{
    "label" => "Label",
    "phone" => "Phone",
    "line1" => "Address Line 1",
    "line2" => "Address Line 2",
    "line3" => "Address Line 3",
    "source" => "Source",
    "source_ref" => "Source Reference",
    "verification_status" => "Verification Status",
    "location" => "Location"
  }

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
         |> assign(:page_title, page_title(address))
         |> assign(:active_nav, :addresses)
         |> assign(:address_id, address_id)
         |> assign(:address, address)
         |> assign(:can_update?, allowed?(current_scope, "admin.address.update"))
         |> assign(:company_context_id, company_context_id)
         |> assign(:countries, countries)
         |> assign(:linked_sort_by, :type)
         |> assign(:linked_sort_dir, :asc)
         |> assign(:field_status, %{})
         |> assign(:editing_field, nil)
         |> assign(:editing_location?, false)
         |> assign_location_form(address)}
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
  # Event Handlers: Inline Text Facts
  # ============================================================================

  @impl true
  def handle_event("save_field", params, socket) do
    if can_update?(socket) do
      case inline_field(params) do
        {:ok, name, field, value} ->
          {:noreply, save_fact(socket, name, %{field => normalize_param(value)}, value)}

        :error ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # ============================================================================
  # Event Handlers: Verification Status Choice
  # ============================================================================

  def handle_event("edit_field", %{"field" => "verification_status"}, socket) do
    if can_update?(socket) do
      {:noreply, assign(socket, :editing_field, "verification_status")}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_field", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end

  def handle_event("save_verification_status", %{"verification_status" => status}, socket)
      when status in @verification_statuses do
    if can_update?(socket) do
      socket =
        socket
        |> assign(:editing_field, nil)
        |> save_fact("verification_status", %{verification_status: status}, status)

      {:noreply, socket}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("save_verification_status", _params, socket) do
    if can_update?(socket) do
      {:noreply,
       socket
       |> assign(:editing_field, nil)
       |> put_field_status(
         "verification_status",
         {:error, "Verification status must be unverified, suggested, or verified."}
       )}
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # ============================================================================
  # Event Handlers: Location Group
  # ============================================================================

  def handle_event("edit_location", _params, socket) do
    if can_update?(socket) do
      {:noreply,
       socket
       |> assign(:editing_location?, true)
       |> assign_location_form(socket.assigns.address)}
    else
      {:noreply, write_forbidden(socket)}
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
    if can_update?(socket) do
      scope = socket.assigns.current_scope.scope

      attrs = %{
        "country_iso" => normalize_param(params["country_iso"]),
        "admin1_code" => normalize_param(params["admin1_code"]),
        "postcode" => normalize_param(params["postcode"]),
        "locality" => normalize_param(params["locality"])
      }

      case Address.update_address(scope, socket.assigns.address_id, attrs) do
        {:ok, _summary} ->
          {:noreply,
           socket
           |> refresh_address()
           |> assign(:editing_location?, false)
           |> put_field_status("location", :saved)
           |> then(&assign_location_form(&1, &1.assigns.address))}

        {:error, %Ecto.Changeset{} = changeset} ->
          # The grouped form reports each refused field on its own input, so
          # the operator corrects it where they typed it.
          {:noreply,
           socket
           |> put_field_status("location", nil)
           |> assign(:location_form, to_form(changeset, as: :location))}

        {:error, reason} ->
          {:noreply, put_field_status(socket, "location", {:error, failure_message(reason)})}
      end
    else
      {:noreply, write_forbidden(socket)}
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
  # Saving
  # ============================================================================

  # One commit, one outcome on the fact that made it. Success refreshes the
  # detail so every projection (title, country name, linked owners) is the
  # server's; refusal keeps the stored value on screen and says what was
  # rejected and why.
  defp save_fact(socket, name, attrs, submitted) do
    scope = socket.assigns.current_scope.scope

    case Address.update_address(scope, socket.assigns.address_id, attrs) do
      {:ok, _summary} ->
        socket
        |> refresh_address()
        |> put_field_status(name, :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        put_field_status(socket, name, {:error, refusal_message(name, submitted, changeset)})

      {:error, reason} ->
        put_field_status(socket, name, {:error, failure_message(reason)})
    end
  end

  defp refresh_address(socket) do
    {:ok, refreshed} =
      Address.get_address_detail(socket.assigns.current_scope.scope, socket.assigns.address_id,
        owner_sort_by: socket.assigns.linked_sort_by,
        owner_sort_dir: socket.assigns.linked_sort_dir
      )

    socket
    |> assign(:address, refreshed)
    |> assign(:page_title, page_title(refreshed))
  end

  # "Saved" belongs to the most recent commit only; a refusal stays on its
  # fact until that fact is committed again, so an unsaved edit is never
  # quietly forgotten.
  defp put_field_status(socket, name, status) do
    statuses =
      socket.assigns.field_status
      |> drop_saved()
      |> Map.put(name, status)

    assign(socket, :field_status, statuses)
  end

  defp drop_saved(statuses) do
    statuses
    |> Enum.reject(fn {_name, value} -> value == :saved end)
    |> Map.new()
  end

  defp refusal_message(name, submitted, %Ecto.Changeset{} = changeset) do
    field = Map.get(@inline_fields, name, :verification_status)

    reasons =
      case translate_errors(changeset.errors, field) do
        [] -> ["could not be saved"]
        messages -> messages
      end

    "#{inspect(rejected_value(submitted))} was not saved: #{fact_label(name)} #{Enum.join(reasons, ", ")}."
  end

  # The alert names what was typed so the refusal is never anonymous, but a
  # long rejected value would push the reason off screen; the first characters
  # identify it and the reason carries the rule that refused it.
  @rejected_value_limit 60
  defp rejected_value(submitted) do
    trimmed = String.trim(to_string(submitted))

    if String.length(trimmed) > @rejected_value_limit do
      String.slice(trimmed, 0, @rejected_value_limit) <> "…"
    else
      trimmed
    end
  end

  defp failure_message(:address_not_found),
    do: "This address no longer exists. Return to the list to find its replacement."

  defp failure_message(_reason),
    do: "The change was not saved. Try again, and tell your administrator if it keeps failing."

  # The refusal is the whole outcome: a "Saved" left over from an earlier
  # commit would read as if this write had landed too.
  defp write_forbidden(socket) do
    socket
    |> assign(:field_status, drop_saved(socket.assigns.field_status))
    |> put_flash(:error, "You do not have permission to update addresses.")
  end

  # Every write re-asks Authz: the `can_update?` assign decides what the page
  # shows, and a grant revoked while the page is open must still be refused.
  defp can_update?(socket) do
    Authz.can(socket.assigns.current_scope.actor, "admin.address.update").allowed
  end

  defp inline_field(params) when is_map(params) do
    Enum.find_value(@inline_fields, :error, fn {name, field} ->
      case Map.fetch(params, name) do
        {:ok, value} when is_binary(value) -> {:ok, name, field, value}
        _ -> nil
      end
    end)
  end

  defp inline_field(_params), do: :error

  defp fact_label(name), do: Map.fetch!(@fact_labels, name)

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
            <div class="flex items-center gap-3">
              <.discovered_panel
                key="record.history"
                id="address-record-history"
                current_scope={@current_scope}
                opts={%{
                  auditable_types: address_auditable_types(),
                  auditable_id: @address.id,
                  title: "History for address ##{@address.id}"
                }}
              />
              <.back_link
                :if={@company_context_id}
                id="address-back-company"
                navigate={~p"/companies/#{@company_context_id}"}
                title="Back to company"
              />
              <.back_link id="address-back-list" navigate={~p"/addresses"} title="Back to addresses" />
            </div>
          </:actions>
        </.header>

        <div class="space-y-6">
          <section
            id="address-details-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-details-heading"
          >
            <h2
              id="address-details-heading"
              class="mb-4 text-xs font-semibold uppercase tracking-wider text-ink-muted"
            >
              Address Details
            </h2>

            <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3">
              <.text_fact
                name="label"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
                class="font-medium"
              />
              <.text_fact
                name="phone"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <div>
                <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                  Verification Status
                </dt>
                <dd id="address-view-verification-status" class="mt-1 text-sm">
                  <button
                    :if={@can_update? and @editing_field != "verification_status"}
                    type="button"
                    id="address-verification-status-display"
                    phx-click="edit_field"
                    phx-value-field="verification_status"
                    aria-label="Edit verification status"
                    aria-describedby={
                      @field_status["verification_status"] && "address-verification-status-status"
                    }
                    class="group -mx-1.5 flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
                  >
                    <.verification_badge status={@address.verification_status} />
                    <.icon
                      name="edit"
                      class="size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                    />
                  </button>

                  <%!-- Window-scoped: the select may not hold focus (JS.focus is
                       best-effort), and Escape must cancel regardless. Only one
                       editor mounts at a time, so the listener is unambiguous. --%>
                  <div
                    :if={@can_update? and @editing_field == "verification_status"}
                    phx-window-keydown="cancel_edit_field"
                    phx-key="Escape"
                  >
                    <form
                      id="address-verification-status-form"
                      phx-change="save_verification_status"
                      class="inline-block"
                    >
                      <select
                        id="address-verification-status"
                        name="verification_status"
                        aria-label="Verification status"
                        phx-mounted={JS.focus()}
                        phx-blur="cancel_edit_field"
                        class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                      >
                        <option
                          :for={{label, value} <- verification_status_options()}
                          value={value}
                          selected={@address.verification_status == value}
                        >
                          {label}
                        </option>
                      </select>
                    </form>
                  </div>

                  <span :if={not @can_update?}>
                    <.verification_badge status={@address.verification_status} />
                  </span>

                  <.commit_status id="address-verification-status-status" status={@field_status["verification_status"]} />
                </dd>
              </div>

              <.text_fact
                name="line1"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <.text_fact
                name="line2"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <.text_fact
                name="line3"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
            </dl>
          </section>

          <section
            id="address-location-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-location-heading"
          >
            <div class="mb-4 flex items-start justify-between gap-3">
              <div>
                <div class="flex items-center gap-2">
                  <h2
                    id="address-location-heading"
                    class="text-xs font-semibold uppercase tracking-wider text-ink-muted"
                  >
                    Geographic Location
                  </h2>
                  <.icon_button
                    :if={@can_update? and not @editing_location?}
                    id="address-edit-location-button"
                    icon="edit"
                    label="Edit location"
                    context={:inline}
                    phx-click="edit_location"
                  />
                </div>
                <p class="mt-0.5 text-xs text-ink-subtle">
                  Linked to GeoNames reference database for standardization and lookup. Country, division, postcode and locality depend on one another, so they are applied together.
                </p>
                <.commit_status id="address-location-status" status={@field_status["location"]} />
              </div>
            </div>

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
                  <.button
                    id="address-save-location"
                    type="submit"
                    variant="primary"
                    phx-disable-with="Applying…"
                  >
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

            <div :if={not @editing_location?} class="mt-4 border-t border-line pt-4">
              <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-4">
                <.fact label="Country">
                  <dd id="address-view-country" class="mt-1 text-sm text-ink">
                    {@address.country_name || @address.country_iso || "—"}
                  </dd>
                </.fact>
                <.fact label="State / Province">
                  <dd id="address-view-admin1" class="mt-1 text-sm text-ink">
                    {@address.admin1_name || @address.admin1_code || "—"}
                  </dd>
                </.fact>
                <.fact label="Postal Code">
                  <dd id="address-view-postcode" class="mt-1 text-sm tabular-nums text-ink">
                    {@address.postcode || "—"}
                  </dd>
                </.fact>
                <.fact label="Locality">
                  <dd id="address-view-locality" class="mt-1 text-sm text-ink">
                    {@address.locality || "—"}
                  </dd>
                </.fact>
              </dl>
            </div>
          </section>

          <section
            id="address-provenance-card"
            class="rounded-2xl border border-line bg-surface p-6 shadow-xs"
            aria-labelledby="address-provenance-heading"
          >
            <div class="mb-4">
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

            <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-4">
              <.text_fact
                name="source"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <.text_fact
                name="source_ref"
                address={@address}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <.fact label="Parser Version">
                <dd id="address-view-parser-version" class="mt-1 text-sm text-ink">
                  {@address.parser_version || "—"}
                </dd>
              </.fact>
              <.fact label="Parse Confidence">
                <dd id="address-view-parse-confidence" class="mt-1 text-sm tabular-nums text-ink">
                  {@address.parse_confidence || "—"}
                </dd>
              </.fact>
              <div :if={@address.raw_input} class="sm:col-span-2 md:col-span-4 mt-2 border-t border-line pt-4">
                <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">
                  Raw Input
                </dt>
                <dd class="mt-1">
                  <pre
                    id="address-view-raw-input"
                    class="overflow-x-auto rounded-xl border border-line bg-surface-muted p-3 font-mono text-xs text-ink"
                  >{@address.raw_input}</pre>
                </dd>
              </div>
            </dl>
          </section>

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
  # Fact Components
  # ============================================================================

  # A read-first text fact. An operator who may update edits it in place; the
  # emptied value is a real edit because every one of these columns is
  # nullable. Anyone else sees the stored value with no affordance.
  attr(:name, :string, required: true)
  attr(:address, Detail, required: true)
  attr(:can_update?, :boolean, required: true)
  attr(:field_status, :map, required: true)
  attr(:class, :any, default: nil)

  defp text_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:value, Map.fetch!(assigns.address, Map.fetch!(@inline_fields, assigns.name)))
      |> assign(:dom_id, "address-#{String.replace(assigns.name, "_", "-")}")

    ~H"""
    <div>
      <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">{@label}</dt>
      <dd id={String.replace(@dom_id, "address-", "address-view-")} class={["mt-1 text-sm text-ink", @class]}>
        <.inline_edit
          :if={@can_update?}
          id={@dom_id}
          name={@name}
          label={@label}
          value={@value || ""}
          id_value={@address.id}
          save_event="save_field"
          allow_empty
          status={@field_status[@name]}
        />
        <span :if={not @can_update?} class={[is_nil(@value) && "text-ink-muted"]}>
          {@value || "—"}
        </span>
      </dd>
    </div>
    """
  end

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-medium uppercase tracking-wider text-ink-subtle">{@label}</dt>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:status, :string, required: true)

  defp verification_badge(assigns) do
    ~H"""
    <.badge kind={verification_badge_kind(@status)}>
      {String.capitalize(@status || "unverified")}
    </.badge>
    """
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp page_title(%Detail{} = address), do: address.label || "Address ##{address.id}"

  defp address_auditable_types,
    do: ["Bilimbi.Core.Address.Schema", Address.auditable_identity()]

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
