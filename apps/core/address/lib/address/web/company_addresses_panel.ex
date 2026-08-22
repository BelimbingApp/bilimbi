defmodule Bilimbi.Core.Address.Web.CompanyAddressesPanel do
  @moduledoc """
  Company-page address panel, contributed as a discovered embed.

  Core Address owns attachment state and every write on this panel; the
  company page renders it by the `"company.addresses"` manifest key and never
  names this module (#595). Ported behaviour-for-behaviour from the company
  show page's former inline section, which reached these operations through
  `function_exported?` probing — the counterpart to the employee-page panel
  (#570/#575).

  Visibility of the edit affordances uses the assign computed on update;
  every write re-evaluates the actor's current grants through `Authz.can/2`
  (the #482/#541/#610 pattern) — mount-time capability state is presentation,
  not an authorization decision. Outcomes render as a panel-local notice
  because a LiveComponent cannot reach the page's flash without a parent
  contract.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Geonames

  import Ecto.Changeset, only: [cast: 3, validate_length: 3, add_error: 4]

  @manage_capability "admin.company.update"
  @valid_address_kinds ~w(headquarters billing shipping branch other)

  # The create-and-attach form's fields, cast as a schemaless changeset — the
  # company page's inline create flow moved here whole (#595). Geonames resolves
  # the cascading country/admin1/postcode/locality selects; core/address already
  # declares the core/geonames edge, so nothing new lands on core/company.
  @address_field_types %{
    label: :string,
    phone: :string,
    line1: :string,
    line2: :string,
    line3: :string,
    country_iso: :string,
    admin1_code: :string,
    postcode: :string,
    locality: :string
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:notice, nil)
     |> assign(:show_attach_modal, false)
     |> assign(:attach_form, to_form(%{}))
     |> assign(:attach_errors, %{})
     |> assign(:editing_priority_address_id, nil)
     |> assign(:edit_priority_value, "0")
     |> assign(:editing_kinds_address_id, nil)
     |> assign(:selected_edit_kinds, [])
     |> assign(:addresses_sort_by, "label")
     |> assign(:addresses_sort_dir, "asc")
     |> assign(:address_kinds, @valid_address_kinds)
     # Create-and-attach flow (ported from the company page's inline section).
     |> assign(:show_create_modal, false)
     |> assign(:address_form, nil)
     |> assign(:address_form_params, %{})
     |> assign(:auto_location, %{admin1_code: false, locality: false})
     |> assign(:admin1_options, [])
     |> assign(:postcode_options, [])
     |> assign(:locality_options, [])
     |> assign(:create_address_kinds, [])
     |> assign(:create_address_is_primary, false)
     |> assign(:create_address_priority, 0)
     |> assign(:countries, Geonames.list_countries())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:can_manage?, allowed?(assigns.current_scope, @manage_capability))
     |> reload()}
  end

  # --- Events (ported from the company page's address section) ---

  @impl true
  def handle_event("open_attach_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_attach_modal, true)
     |> assign(
       :attach_form,
       to_form(%{
         "address_id" => "",
         "kinds" => [],
         "is_primary" => false,
         "priority" => "0"
       })
     )
     |> assign(:attach_errors, %{})}
  end

  def handle_event("close_attach_modal", _params, socket) do
    {:noreply, assign(socket, :show_attach_modal, false)}
  end

  def handle_event("attach_address", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      addr_params = params["address"] || params
      address_id_str = addr_params["address_id"] || ""

      kinds =
        case addr_params["kinds"] do
          list when is_list(list) -> Enum.filter(list, &(&1 in @valid_address_kinds))
          str when is_binary(str) and str != "" -> [str]
          _ -> []
        end

      is_primary = addr_params["is_primary"] in [true, "true", "1", 1]

      priority_int =
        case Integer.parse(to_string(addr_params["priority"] || "0")) do
          {p, ""} when p >= 0 -> p
          _ -> 0
        end

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          attrs = %{kind: kinds, is_primary: is_primary, priority: priority_int}

          case Address.attach_to_company(scope, address_id, socket.assigns.company_id, attrs) do
            {:ok, :attached} ->
              {:noreply,
               socket
               |> notice(:info, "Address attached.")
               |> assign(:show_attach_modal, false)
               |> reload()}

            {:error, _} ->
              {:noreply, notice(socket, :error, "Failed to attach address.")}
          end

        _ ->
          {:noreply,
           socket
           |> assign(:attach_errors, %{address_id: "Please select an address."})
           |> assign(:attach_form, to_form(addr_params))}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("detach_address", %{"id" => address_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          case Address.detach_from_company(scope, address_id, socket.assigns.company_id) do
            :ok ->
              {:noreply, socket |> notice(:info, "Address unlinked.") |> reload()}

            {:error, _} ->
              {:noreply, notice(socket, :error, "Failed to unlink address.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("toggle_address_primary", %{"id" => address_id_str}, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope

      case parse_id(address_id_str) do
        address_id when is_integer(address_id) and address_id > 0 ->
          target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
          new_primary = if target_addr, do: not target_addr.is_primary, else: true

          case Address.update_company_attachment(
                 scope,
                 address_id,
                 socket.assigns.company_id,
                 %{
                   is_primary: new_primary
                 }
               ) do
            {:ok, :updated} ->
              {:noreply, socket |> notice(:info, "Address setting updated.") |> reload()}

            {:error, _} ->
              {:noreply, notice(socket, :error, "Failed to update address setting.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_address_priority", %{"id" => address_id_str}, socket) do
    case parse_id(address_id_str) do
      address_id when is_integer(address_id) and address_id > 0 ->
        target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
        val = if target_addr, do: to_string(target_addr.priority), else: "0"

        {:noreply,
         socket
         |> assign(:editing_priority_address_id, address_id)
         |> assign(:edit_priority_value, val)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_address_priority", _params, socket) do
    {:noreply, assign(socket, :editing_priority_address_id, nil)}
  end

  def handle_event("save_address_priority", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope

      address_id =
        socket.assigns.editing_priority_address_id || params["address_id"] || params["id"]

      prio_val = params["priority"] || params["value"] || "0"

      priority_int =
        case Integer.parse(to_string(prio_val)) do
          {p, ""} when p >= 0 -> p
          _ -> 0
        end

      case parse_id(address_id) do
        id when is_integer(id) and id > 0 ->
          case Address.update_company_attachment(scope, id, socket.assigns.company_id, %{
                 priority: priority_int
               }) do
            {:ok, :updated} ->
              {:noreply,
               socket
               |> notice(:info, "Address setting updated.")
               |> assign(:editing_priority_address_id, nil)
               |> reload()}

            {:error, _} ->
              {:noreply, notice(socket, :error, "Failed to update priority.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("edit_address_kinds", %{"id" => address_id_str}, socket) do
    case parse_id(address_id_str) do
      address_id when is_integer(address_id) and address_id > 0 ->
        target_addr = Enum.find(socket.assigns.attached_addresses, &(&1.id == address_id))
        kinds = if target_addr, do: target_addr.kind || [], else: []

        {:noreply,
         socket
         |> assign(:editing_kinds_address_id, address_id)
         |> assign(:selected_edit_kinds, kinds)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_address_kinds", _params, socket) do
    {:noreply, assign(socket, :editing_kinds_address_id, nil)}
  end

  def handle_event("toggle_edit_kind", %{"kind" => kind}, socket) do
    current = socket.assigns.selected_edit_kinds

    updated =
      if kind in current do
        List.delete(current, kind)
      else
        [kind | current]
      end

    {:noreply, assign(socket, :selected_edit_kinds, updated)}
  end

  def handle_event("save_address_kinds", params, socket) do
    if can_manage?(socket) do
      scope = socket.assigns.current_scope.scope
      address_id = socket.assigns.editing_kinds_address_id || params["address_id"] || params["id"]

      kinds =
        case params["kinds"] do
          list when is_list(list) -> Enum.filter(list, &(&1 in @valid_address_kinds))
          _ -> socket.assigns.selected_edit_kinds
        end

      case parse_id(address_id) do
        id when is_integer(id) and id > 0 ->
          case Address.update_company_attachment(scope, id, socket.assigns.company_id, %{
                 kind: kinds
               }) do
            {:ok, :updated} ->
              {:noreply,
               socket
               |> notice(:info, "Address kinds updated.")
               |> assign(:editing_kinds_address_id, nil)
               |> reload()}

            {:error, _} ->
              {:noreply, notice(socket, :error, "Failed to update address kinds.")}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("sort_addresses", params, socket) do
    sort_col = params["sort_by"] || params["sort"] || "label"
    current_dir = socket.assigns.addresses_sort_dir
    current_col = socket.assigns.addresses_sort_by

    new_dir =
      if current_col == sort_col and current_dir == "asc" do
        "desc"
      else
        "asc"
      end

    sorted = sort_addresses(socket.assigns.attached_addresses, sort_col, new_dir)

    {:noreply,
     socket
     |> assign(:addresses_sort_by, sort_col)
     |> assign(:addresses_sort_dir, new_dir)
     |> assign(:sorted_addresses, sorted)}
  end

  # --- Create-and-attach: a new address made and linked in one step ---

  def handle_event("open_create_modal", _params, socket) do
    params = %{"country_iso" => "MY"}

    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:address_form_params, params)
     |> assign(:auto_location, %{admin1_code: false, locality: false})
     |> assign(:create_address_kinds, [])
     |> assign(:create_address_is_primary, false)
     |> assign(:create_address_priority, 0)
     |> assign_address_form(address_form_changeset(params))
     |> assign_address_location_options(params)}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply, socket |> assign(:show_create_modal, false) |> assign(:address_form, nil)}
  end

  def handle_event("validate_create_address", %{"address" => incoming}, socket) do
    {params, auto_location} = address_location_params(socket, incoming)

    kinds = Map.get(incoming, "kinds") || socket.assigns.create_address_kinds
    is_primary = incoming["is_primary"] in [true, "true", "1"]

    priority =
      case Integer.parse(incoming["priority"] || "0") do
        {p, _} -> p
        _ -> socket.assigns.create_address_priority
      end

    {:noreply,
     socket
     |> assign(:address_form_params, params)
     |> assign(:auto_location, auto_location)
     |> assign(:create_address_kinds, kinds)
     |> assign(:create_address_is_primary, is_primary)
     |> assign(:create_address_priority, priority)
     |> assign_address_form(address_form_changeset(params))
     |> assign_address_location_options(params)}
  end

  def handle_event("save_create_address", %{"address" => incoming}, socket) do
    if can_manage?(socket) do
      {params, auto_location} = address_location_params(socket, incoming)
      changeset = address_form_changeset(params)
      scope = socket.assigns.current_scope.scope

      if changeset.valid? do
        kinds = Map.get(incoming, "kinds") || socket.assigns.create_address_kinds
        is_primary = incoming["is_primary"] in [true, "true", "1"]

        priority =
          case Integer.parse(incoming["priority"] || "0") do
            {p, _} -> p
            _ -> socket.assigns.create_address_priority
          end

        attachment_attrs = %{
          kind: kinds,
          is_primary: is_primary,
          priority: priority,
          valid_from: Date.utc_today()
        }

        case Address.create_and_attach_to_company(
               scope,
               socket.assigns.company_id,
               params,
               attachment_attrs
             ) do
          {:ok, _address} ->
            {:noreply,
             socket
             |> notice(:info, "Address created and attached.")
             |> assign(:show_create_modal, false)
             |> assign(:address_form, nil)
             |> reload()}

          {:error, %Ecto.Changeset{} = domain_changeset} ->
            {:noreply,
             socket
             |> assign(:address_form_params, params)
             |> assign(:auto_location, auto_location)
             |> assign_address_form(copy_address_domain_errors(changeset, domain_changeset))
             |> assign_address_location_options(params)}

          {:error, reason} ->
            {:noreply, notice(socket, :error, "Failed to create address: #{inspect(reason)}")}
        end
      else
        {:noreply,
         socket
         |> assign(:address_form_params, params)
         |> assign(:auto_location, auto_location)
         |> assign_address_form(changeset)
         |> assign_address_location_options(params)}
      end
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  # --- Data & helpers ---

  defp reload(socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company_id

    # Deliberately strict: the page resolved this company before rendering the
    # panel, so a non-ok here is infrastructure failure or a mid-session
    # deletion — raising reaches the recovery boundary instead of rendering a
    # broken section as an empty one (#409).
    {:ok, attached} = Address.list_company_attached_addresses(scope, company_id)
    {:ok, available} = Address.list_available_company_addresses(scope, company_id)

    sorted =
      sort_addresses(
        attached,
        socket.assigns.addresses_sort_by,
        socket.assigns.addresses_sort_dir
      )

    socket
    |> assign(:attached_addresses, attached)
    |> assign(:available_addresses, available)
    |> assign(:sorted_addresses, sorted)
  end

  defp can_manage?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @manage_capability).allowed
  end

  defp write_forbidden(socket) do
    socket
    |> assign(:can_manage?, false)
    |> notice(:error, "You do not have permission to edit companies.")
  end

  defp notice(socket, kind, message), do: assign(socket, :notice, {kind, message})

  # --- Create-form location cascade (Geonames-backed, ported from show_live) ---

  defp address_location_params(socket, incoming) do
    old = socket.assigns.address_form_params
    old_auto = socket.assigns.auto_location

    incoming = normalize_address_country(incoming)
    country_changed? = field(incoming, "country_iso") != field(old, "country_iso")
    postcode_changed? = field(incoming, "postcode") != field(old, "postcode")

    cond do
      country_changed? ->
        {clear_address_location_dependents(incoming), %{admin1_code: false, locality: false}}

      postcode_changed? and field(incoming, "postcode") != "" ->
        auto_fill_address_location(incoming, old_auto)

      true ->
        {incoming, old_auto}
    end
  end

  defp auto_fill_address_location(params, old_auto) do
    params =
      params
      |> maybe_clear_auto("admin1_code", old_auto.admin1_code)
      |> maybe_clear_auto("locality", old_auto.locality)

    matches = Geonames.lookup_postcode(field(params, "country_iso"), field(params, "postcode"))

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

  defp assign_address_location_options(socket, params) do
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

  defp address_form_changeset(params) do
    {%{}, @address_field_types}
    |> cast(params, Map.keys(@address_field_types))
    |> validate_length(:label, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_length(:locality, max: 255)
    |> validate_length(:postcode, max: 255)
    |> validate_length(:country_iso, is: 2)
    |> validate_length(:admin1_code, max: 20)
    |> Map.put(:action, :validate)
  end

  defp copy_address_domain_errors(form_changeset, %Ecto.Changeset{} = domain_changeset) do
    domain_changeset.errors
    |> Enum.reduce(form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@address_field_types, field),
        do: add_error(acc, field, message, opts),
        else: acc
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_address_form(socket, %Ecto.Changeset{} = changeset),
    do: assign(socket, :address_form, to_form(changeset, as: :address))

  defp normalize_address_country(params) do
    Map.update(params, "country_iso", "", fn value ->
      value |> to_string() |> String.trim() |> String.upcase()
    end)
  end

  defp clear_address_location_dependents(params) do
    Enum.reduce(~w(admin1_code postcode locality), params, &Map.put(&2, &1, ""))
  end

  defp maybe_clear_auto(params, field_name, true), do: Map.put(params, field_name, "")
  defp maybe_clear_auto(params, _field_name, false), do: params

  defp field(params, name), do: Map.get(params, name, "")
  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="contents">
      <div
        :if={@notice}
        id={"#{@id}-notice"}
        class={[
          "mb-3 rounded-lg border px-3 py-2 text-sm",
          elem(@notice, 0) == :info && "border-line bg-brand-surface text-ink",
          elem(@notice, 0) == :error && "border-danger/40 bg-surface text-danger"
        ]}
      >
        {elem(@notice, 1)}
      </div>
          <!-- Card 4: Attached Addresses -->
          <.card id="addresses-card">
            <div class="p-5 sm:p-6 space-y-4">
              <div class="flex items-center justify-between">
                <h3 class="text-[11px] uppercase tracking-wider font-semibold text-ink-subtle flex items-center gap-1.5">
                  <span>Addresses</span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink">
                    {length(@attached_addresses)}
                  </span>
                </h3>

                <div :if={@can_manage?} class="flex items-center gap-2">
                  <.button
                    id="btn-open-attach-address"
                    phx-click="open_attach_modal"
                    phx-target={@myself}
                    class="text-xs px-2.5 py-1"
                  >
                    <.icon name="bilimbi-plus" class="size-3.5" /> <span>Attach Address</span>
                  </.button>
                  <.button
                    id="btn-open-create-address"
                    phx-click="open_create_modal"
                    phx-target={@myself}
                    variant="primary"
                    class="text-xs px-2.5 py-1"
                  >
                    <.icon name="bilimbi-plus" class="size-3.5" /> <span>Create &amp; Attach</span>
                  </.button>
                </div>
              </div>

              <div class="overflow-x-auto">
                <table id="addresses-table" class="w-full text-left text-xs text-ink">
                  <thead>
                    <tr class="border-b border-line text-ink-subtle">
                      <th class="py-2 pr-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="label"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Label</span>
                          <%= if @addresses_sort_by == "label" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="line1"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Address</span>
                          <%= if @addresses_sort_by == "line1" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="kind"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Kind</span>
                          <%= if @addresses_sort_by == "kind" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="is_primary"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Primary</span>
                          <%= if @addresses_sort_by == "is_primary" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="priority"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Priority</span>
                          <%= if @addresses_sort_by == "priority" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="valid_from"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Valid From</span>
                          <%= if @addresses_sort_by == "valid_from" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th class="py-2 px-3 font-semibold">
                        <button
                          type="button"
                          phx-click="sort_addresses" phx-target={@myself}
                          phx-value-sort_by="valid_to"
                          class="flex items-center gap-1 hover:text-ink cursor-pointer"
                        >
                          <span>Valid To</span>
                          <%= if @addresses_sort_by == "valid_to" do %>
                            <span>{if @addresses_sort_dir == "asc", do: "↑", else: "↓"}</span>
                          <% end %>
                        </button>
                      </th>

                      <th :if={@can_manage?} class="py-2 pl-3 text-right font-semibold">Actions</th>
                    </tr>
                  </thead>

                  <tbody class="divide-y divide-line">
                    <%= if @sorted_addresses == [] do %>
                      <tr>
                        <td
                          colspan={if @can_manage?, do: 8, else: 7}
                          class="py-6 text-center text-ink-subtle"
                        >
                          No addresses linked.
                        </td>
                      </tr>
                    <% else %>
                      <%= for addr <- @sorted_addresses do %>
                        <tr
                          id={"address-row-#{addr.id}"}
                          class="hover:bg-surface-sunken/40 transition"
                        >
                          <td class="py-2 pr-3 font-medium text-ink">
                            <span>{addr.label || "Address #{addr.id}"}</span>
                          </td>

                          <td class="py-2 px-3 text-ink-subtle">
                            {format_address_summary(addr)}
                          </td>

                          <td class="py-2 px-3">
                            <%= if @editing_kinds_address_id == addr.id do %>
                              <div class="space-y-1">
                                <%= for k <- @address_kinds do %>
                                  <label class="flex items-center gap-1.5 text-xs cursor-pointer">
                                    <input
                                      type="checkbox"
                                      value={k}
                                      checked={k in @selected_edit_kinds}
                                      phx-click="toggle_edit_kind" phx-target={@myself}
                                      phx-value-kind={k}
                                      class="rounded border-line"
                                    /> <span>{String.capitalize(k)}</span>
                                  </label>
                                <% end %>

                                <div class="flex items-center gap-1 pt-1">
                                  <.button
                                    id={"save-kinds-#{addr.id}"}
                                    type="button"
                                    phx-click="save_address_kinds" phx-target={@myself}
                                    phx-value-address_id={addr.id}
                                    variant="primary"
                                    class="text-xs px-2 py-0.5"
                                  >
                                    Save
                                  </.button>

                                  <.button
                                    id={"cancel-kinds-#{addr.id}"}
                                    type="button"
                                    phx-click="cancel_address_kinds" phx-target={@myself}
                                    class="text-xs px-2 py-0.5"
                                  >
                                    Cancel
                                  </.button>
                                </div>
                              </div>
                            <% else %>
                              <div
                                phx-click={if @can_manage?, do: "edit_address_kinds"}
                                phx-target={@myself}
                                phx-value-id={addr.id}
                                class={[
                                  "flex flex-wrap gap-1 items-center",
                                  @can_manage? && "cursor-pointer hover:opacity-80"
                                ]}
                              >
                                <%= if addr.kind == [] do %>
                                  <span class="text-ink-subtle">—</span>
                                <% else %>
                                  <%= for k <- addr.kind do %>
                                    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-surface-muted text-ink border border-line">
                                      {String.capitalize(k)}
                                    </span>
                                  <% end %>
                                <% end %>

                                <.icon
                                  :if={@can_manage?}
                                  name="bilimbi-pencil"
                                  class="size-3 text-ink-subtle ml-0.5"
                                />
                              </div>
                            <% end %>
                          </td>

                          <td class="py-2 px-3">
                            <%= if @can_manage? do %>
                              <button
                                id={"toggle-primary-#{addr.id}"}
                                type="button"
                                phx-click="toggle_address_primary" phx-target={@myself}
                                phx-value-id={addr.id}
                                class="cursor-pointer"
                                title="Toggle primary status"
                              >
                                <%= if addr.is_primary do %>
                                  <.badge kind={:success}>Yes</.badge>
                                <% else %>
                                  <span class="text-ink-subtle hover:text-ink">No</span>
                                <% end %>
                              </button>
                            <% else %>
                              <%= if addr.is_primary do %>
                                <.badge kind={:success}>Yes</.badge>
                              <% else %>
                                <span class="text-ink-subtle">No</span>
                              <% end %>
                            <% end %>
                          </td>

                          <td class="py-2 px-3 tabular-nums">
                            <%= if @editing_priority_address_id == addr.id do %>
                              <form
                                phx-submit="save_address_priority" phx-target={@myself}
                                id={"priority-form-#{addr.id}"}
                                class="flex items-center gap-1"
                              >
                                <input type="hidden" name="address_id" value={addr.id} />
                                <input
                                  type="number"
                                  name="priority"
                                  id={"input-priority-#{addr.id}"}
                                  value={@edit_priority_value}
                                  min="0"
                                  class="w-14 rounded border border-line bg-surface px-1.5 py-0.5 text-xs text-ink"
                                />
                                <.button type="submit" variant="primary" class="text-xs px-2 py-0.5">✓</.button>
                                <.button
                                  type="button"
                                  phx-click="cancel_address_priority" phx-target={@myself}
                                  class="text-xs px-2 py-0.5"
                                >✕</.button>
                              </form>
                            <% else %>
                              <div
                                phx-click={if @can_manage?, do: "edit_address_priority"}
                                phx-target={@myself}
                                phx-value-id={addr.id}
                                class={[
                                  "inline-flex items-center gap-1",
                                  @can_manage? && "cursor-pointer hover:opacity-80"
                                ]}
                              >
                                <span>{addr.priority || 0}</span>
                                <.icon
                                  :if={@can_manage?}
                                  name="bilimbi-pencil"
                                  class="size-3 text-ink-subtle"
                                />
                              </div>
                            <% end %>
                          </td>

                          <td class="py-2 px-3 tabular-nums text-ink-subtle">
                            {display_or_dash(addr.valid_from)}
                          </td>

                          <td class="py-2 px-3 tabular-nums text-ink-subtle">
                            {display_or_dash(addr.valid_to)}
                          </td>

                          <td :if={@can_manage?} class="py-2 pl-3 text-right">
                            <.button
                              id={"unlink-address-#{addr.id}"}
                              type="button"
                              phx-click="detach_address" phx-target={@myself}
                              phx-value-id={addr.id}
                              data-confirm="Are you sure you want to unlink this address?"
                              class="text-danger hover:bg-danger/10 text-xs px-2 py-1"
                            >
                              <.icon name="bilimbi-link-slash" class="size-3.5" />
                              <span class="sr-only">Unlink</span>
                            </.button>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </.card>
              <!-- Attach Address Modal Dialog -->
              <div
          :if={@show_attach_modal}
          id="attach-address-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
              >
          <div class="mt-16 w-full max-w-lg rounded-2xl border border-line bg-surface p-6 shadow-lg space-y-4">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Attach Address
            </h3>

            <p class="text-xs text-ink-muted">
              Select an address to attach to this company.
            </p>

            <.form
              for={@attach_form}
              phx-submit="attach_address" phx-target={@myself}
              id="attach-address-modal-form"
              class="space-y-4"
            >
              <div>
                <label
                  for="company-attach-address"
                  class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1"
                >
                  Address
                </label>

                <select
                  id="company-attach-address"
                  name="address[address_id]"
                  class="w-full rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                >
                  <option value="">Select an address...</option>

                  <%= for addr <- @available_addresses do %>
                    <option value={addr.id}>
                      {addr.label} — {format_address_summary(addr)}
                    </option>
                  <% end %>
                </select>

                <%= if Map.has_key?(@attach_errors, :address_id) do %>
                  <p class="text-xs text-danger mt-1">{@attach_errors.address_id}</p>
                <% end %>
              </div>

              <div>
                <span class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1">
                  Kind
                </span>

                <div class="flex flex-wrap gap-x-4 gap-y-2">
                  <%= for k <- @address_kinds do %>
                    <label class="flex items-center gap-2 text-xs text-ink cursor-pointer">
                      <input
                        id={"company-attach-kind-#{k}"}
                        type="checkbox"
                        name="address[kinds][]"
                        value={k}
                        class="rounded border-line"
                      /> <span>{String.capitalize(k)}</span>
                    </label>
                  <% end %>
                </div>
              </div>

              <div class="flex items-center gap-2">
                <input
                  id="company-attach-is-primary"
                  type="checkbox"
                  name="address[is_primary]"
                  value="true"
                  class="rounded border-line"
                />
                <label
                  for="company-attach-is-primary"
                  class="text-xs font-medium text-ink cursor-pointer"
                >
                  Primary Address
                </label>
              </div>

              <div>
                <label
                  for="company-attach-priority"
                  class="block text-xs font-semibold text-ink-subtle uppercase tracking-wider mb-1"
                >
                  Priority
                </label>

                <input
                  id="company-attach-priority"
                  type="number"
                  name="address[priority]"
                  value="0"
                  min="0"
                  class="w-24 rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
                />
                <p class="text-xs text-ink-subtle mt-1">
                  Lower number = higher priority. Used to order addresses of the same kind (0 = top).
                </p>
              </div>

              <div class="flex items-center justify-end gap-2 pt-2 border-t border-line">
                <.button type="button" phx-click="close_attach_modal" phx-target={@myself} class="text-xs px-3 py-1.5">
                  Cancel
                </.button>

                <.button
                  id="btn-submit-attach-address"
                  type="submit"
                  variant="primary"
                  class="text-xs px-3 py-1.5"
                >
                  Attach
                </.button>
              </div>
            </.form>
          </div>
              </div>

      <%!-- Create & attach: a new address made and linked in one step (#595). --%>
      <div
        :if={@show_create_modal}
        id="company-create-address-modal"
        class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-ink/40 p-4"
      >
        <div class="w-full max-w-2xl rounded-2xl border border-line bg-surface p-6 shadow-xl">
          <h3 class="text-base font-semibold text-ink-strong mb-4">Create &amp; Attach Address</h3>

          <.form
            for={@address_form}
            id="create-attach-address-form"
            phx-change="validate_create_address"
            phx-submit="save_create_address"
            phx-target={@myself}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@address_form[:label]} id="create-address-label" label="Label" />
              <.input field={@address_form[:phone]} id="create-address-phone" label="Phone" type="tel" />
            </div>

            <.input field={@address_form[:line1]} id="create-address-line1" label="Address Line 1" />
            <.input field={@address_form[:line2]} id="create-address-line2" label="Address Line 2" />
            <.input field={@address_form[:line3]} id="create-address-line3" label="Address Line 3" />

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input
                type="select"
                field={@address_form[:country_iso]}
                id="create-address-country-iso"
                label="Country"
                options={country_options(@countries)}
              />
              <.input
                type="select"
                field={@address_form[:admin1_code]}
                id="create-address-admin1-code"
                label="State / Province"
                prompt="Select state..."
                options={admin1_options(@admin1_options)}
              />
            </div>

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@address_form[:postcode]} id="create-address-postcode" label="Postcode" />
              <.input field={@address_form[:locality]} id="create-address-locality" label="Locality" />
            </div>

            <div class="border-t border-line pt-4">
              <h4 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle mb-3">
                Link Settings
              </h4>
              <div class="space-y-3">
                <div>
                  <span class="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-ink-subtle">
                    Kind
                  </span>
                  <div class="flex flex-wrap gap-4">
                    <label
                      :for={kind <- @address_kinds}
                      class="flex items-center gap-2 text-sm text-ink cursor-pointer"
                    >
                      <input
                        type="checkbox"
                        name="address[kinds][]"
                        value={kind}
                        checked={kind in @create_address_kinds}
                        class="rounded border-line text-action focus:ring-action"
                      />
                      {String.capitalize(kind)}
                    </label>
                  </div>
                </div>

                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <label class="flex items-center gap-2 text-sm text-ink cursor-pointer mt-6">
                    <input
                      type="checkbox"
                      name="address[is_primary]"
                      value="true"
                      checked={@create_address_is_primary}
                      class="rounded border-line text-action focus:ring-action"
                    />
                    Primary Address
                  </label>

                  <div>
                    <label for="create-address-priority" class="mb-1.5 block text-sm font-medium text-ink">
                      Priority
                    </label>
                    <input
                      type="number"
                      name="address[priority]"
                      id="create-address-priority"
                      value={@create_address_priority}
                      min="0"
                      class="w-28 rounded-xl border border-line bg-surface px-3 py-2 text-sm text-ink focus:outline-none focus:ring-1 focus:ring-action"
                    />
                  </div>
                </div>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 pt-4 border-t border-line">
              <.button type="button" phx-click="close_create_modal" phx-target={@myself}>
                Cancel
              </.button>
              <.button id="btn-submit-create-address" type="submit" variant="primary">
                Create &amp; Attach
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp country_options(countries),
    do: Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})

  defp admin1_options(admin1), do: Enum.map(admin1, &{&1.name, &1.code})

  defp sort_addresses(addresses, sort_by, sort_dir) do
    mult = if sort_dir == "desc", do: -1, else: 1

    Enum.sort(addresses, fn a, b ->
      case sort_by do
        "label" ->
          compare_strings(a.label || "", b.label || "", mult, a.id, b.id)

        "line1" ->
          compare_strings(a.line1 || "", b.line1 || "", mult, a.id, b.id)

        "kind" ->
          kinds_a = Enum.join(Enum.sort(a.kind || []), ",")
          kinds_b = Enum.join(Enum.sort(b.kind || []), ",")
          compare_strings(kinds_a, kinds_b, mult, a.id, b.id)

        "is_primary" ->
          val_a = if a.is_primary, do: 1, else: 0
          val_b = if b.is_primary, do: 1, else: 0
          compare_integers(val_a, val_b, mult, a.id, b.id)

        "priority" ->
          compare_integers(a.priority || 0, b.priority || 0, mult, a.id, b.id)

        "valid_from" ->
          str_a = if a.valid_from, do: Date.to_iso8601(a.valid_from), else: ""
          str_b = if b.valid_from, do: Date.to_iso8601(b.valid_from), else: ""
          compare_strings(str_a, str_b, mult, a.id, b.id)

        "valid_to" ->
          str_a = if a.valid_to, do: Date.to_iso8601(a.valid_to), else: ""
          str_b = if b.valid_to, do: Date.to_iso8601(b.valid_to), else: ""
          compare_strings(str_a, str_b, mult, a.id, b.id)

        _ ->
          compare_strings(a.label || "", b.label || "", mult, a.id, b.id)
      end
    end)
  end

  defp compare_strings(a, b, mult, id_a, id_b) do
    case {a, b} do
      {x, y} when x == y ->
        id_a <= id_b

      {x, y} ->
        cmp = if String.downcase(x) < String.downcase(y), do: -1, else: 1
        cmp * mult < 0
    end
  end

  defp compare_integers(a, b, mult, id_a, id_b) do
    case {a, b} do
      {x, y} when x == y ->
        id_a <= id_b

      {x, y} ->
        cmp = if x < y, do: -1, else: 1
        cmp * mult < 0
    end
  end

  defp format_address_summary(addr) do
    [addr.line1, addr.locality, addr.country_iso]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp display_or_dash(nil), do: "—"
  defp display_or_dash(""), do: "—"
  defp display_or_dash(value), do: to_string(value)

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
