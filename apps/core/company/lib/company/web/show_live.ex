defmodule Bilimbi.Core.Company.Web.ShowLive do
  @moduledoc """
  Company profile: identity, addresses, timezone settings, subsidiaries,
  departments, relationships, external accesses, users, and employees —
  all accessed through declared public domain APIs.
  """

  use Bilimbi.Base.UI, :live_view

  # Assign-only staging for the activity and metadata forms: these events
  # mirror the input into socket assigns and write nothing to the domain.
  # The persisting events (`add_activity`, `save_metadata`) sit behind the
  # `@write_events` deny clause below (#420).
  @write_guard_opt_out ~w(update_metadata_input update_new_activity)

  alias Bilimbi.Base.PrincipalDirectory
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Geonames

  @common_timezones [
    "UTC",
    "Africa/Cairo",
    "Africa/Johannesburg",
    "Africa/Lagos",
    "America/Argentina/Buenos_Aires",
    "America/Bogota",
    "America/Chicago",
    "America/Denver",
    "America/Los_Angeles",
    "America/Mexico_City",
    "America/New_York",
    "America/Sao_Paulo",
    "America/Toronto",
    "America/Vancouver",
    "Asia/Bangkok",
    "Asia/Dubai",
    "Asia/Hong_Kong",
    "Asia/Jakarta",
    "Asia/Kolkata",
    "Asia/Kuala_Lumpur",
    "Asia/Manila",
    "Asia/Seoul",
    "Asia/Shanghai",
    "Asia/Singapore",
    "Asia/Taipei",
    "Asia/Tokyo",
    "Australia/Melbourne",
    "Australia/Perth",
    "Australia/Sydney",
    "Europe/Amsterdam",
    "Europe/Berlin",
    "Europe/Dublin",
    "Europe/London",
    "Europe/Madrid",
    "Europe/Paris",
    "Europe/Rome",
    "Europe/Zurich",
    "Pacific/Auckland",
    "Pacific/Honolulu"
  ]

  @page_sizes [25, 50, 100, 300]
  @default_page 1
  @default_page_size 25

  @table_defaults %{
    users: %{search: nil, sort_by: "name", sort_dir: :asc, page: 1, per_page: 25},
    employees: %{search: nil, sort_by: "full_name", sort_dir: :asc, page: 1, per_page: 25}
  }

  @table_sorts %{
    users: ~w(name email email_verified),
    employees: ~w(full_name employee_number employee_type status)
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    case Integer.parse(id) do
      {company_id, ""} -> load_company(socket, scope, company_id)
      _ -> {:ok, not_found(socket)}
    end
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{company: _company}} = socket) do
    table_state = table_state_from_params(params)

    {:noreply,
     socket
     |> assign(:table_state, table_state)
     |> refresh_show_table_pages()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load_company(socket, scope, company_id) do
    case Company.get_company(scope, company_id) do
      {:ok, company} ->
        is_primary = Company.primary_company?(scope, company_id)
        legal_entity_types = Company.list_legal_entity_types() |> elem(1)
        countries = list_geonames_countries()
        parent_companies = load_parent_companies(scope, company_id)
        children = Company.list_child_companies(scope, company_id) |> elem(1)
        departments = Company.list_departments(scope, company_id) |> elem(1)
        department_head_names = resolve_department_heads(scope, departments)
        relationships = Company.list_relationships(scope, company_id) |> elem(1)
        external_accesses = Company.list_external_accesses(scope, company_id) |> elem(1)
        external_access_users = load_external_access_users(scope, external_accesses)
        company_timezone = get_company_timezone(company)

        {:ok,
         socket
         |> assign(:page_title, Company.Summary.display_name(company))
         |> assign(:active_nav, "admin.company")
         |> assign(:company, company)
         |> assign(:is_primary, is_primary)
         |> assign(:can_update?, allowed?(socket.assigns.current_scope, "admin.company.update"))
         |> assign(:legal_entity_types, legal_entity_types)
         |> assign(:countries, countries)
         |> assign(:parent_companies, parent_companies)
         |> assign(:children, children)
         |> assign(:departments, departments)
         |> assign(:department_head_names, department_head_names)
         |> assign(:relationships, relationships)
         |> assign(:external_accesses, external_accesses)
         |> assign(:external_access_users, external_access_users)
         |> assign(:page_sizes, @page_sizes)
         |> assign(:table_state, default_table_state())
         |> assign(:company_timezone, company_timezone || "")
         |> assign(:timezone_options, @common_timezones)
         |> assign(:modal_action, nil)
         |> assign(:details_form, nil)
         |> assign(:new_activity, "")
         |> assign(:editing_metadata?, false)
         |> assign(:metadata_input, format_metadata(company.metadata))
         |> refresh_show_table_pages()}

      {:error, :not_found} ->
        {:ok, not_found(socket)}
    end
  end

  defp load_parent_companies(scope, company_id) do
    case Company.list_companies(scope) do
      {:ok, companies} -> Enum.reject(companies, &(&1.id == company_id))
    end
  end

  # A department's head is an employee, which core/company cannot name across the
  # module boundary. base/principal_directory resolves the `{:employee, id}`
  # identities through the employee-owned provider (ADR 0011/0014), so this file
  # never depends on core/employee. Returns a head_id => name map; unresolved or
  # headless departments simply fall back to "—" in the table.
  defp resolve_department_heads(scope, departments) do
    candidates =
      departments
      |> Enum.map(& &1.head_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{:employee, &1})

    with [_ | _] <- candidates,
         {:ok, named} <- PrincipalDirectory.rank(scope, candidates) do
      Map.new(named, fn %{id: id, name: name} -> {id, name} end)
    else
      _ -> %{}
    end
  end

  defp get_company_timezone(company) do
    Settings.get("localization.timezone", SettingsScope.company(company.id, company.tenant_id))
  rescue
    _ -> nil
  end

  # ============================================================================
  # Dynamic Integration with Core User
  # (Geonames is a declared dependency — call Bilimbi.Core.Geonames directly for
  #  the jurisdiction country label. Employees render through the
  #  core/employee-owned "company.employees" discovered embed and addresses
  #  through the core/address-owned "company.addresses" embed (#595), so this
  #  file no longer probes Core.Employee or Core.Address.)
  # ============================================================================

  defp load_external_access_users(scope, external_accesses) do
    user_mod = Module.concat(["Bilimbi", "Core", "User"])

    user_ids =
      external_accesses
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    cond do
      user_ids == [] ->
        %{}

      Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :get_tenant_users, 2) ->
        case apply(user_mod, :get_tenant_users, [scope, user_ids]) do
          {:ok, users_map} -> users_map
          _ -> %{}
        end

      Code.ensure_loaded?(user_mod) and function_exported?(user_mod, :get_tenant_user, 2) ->
        Enum.reduce(user_ids, %{}, fn user_id, acc ->
          case apply(user_mod, :get_tenant_user, [scope, user_id]) do
            {:ok, user} -> Map.put(acc, user_id, user)
            _ -> acc
          end
        end)

      true ->
        %{}
    end
  end

  # Geonames is a declared company dependency (bilimbi.module.exs). Call it
  # directly — the same pattern create_live.ex already uses. Do not probe.
  defp list_geonames_countries, do: Geonames.list_countries()

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That company does not exist in this workspace.")
    |> push_navigate(to: ~p"/companies")
  end

  defp format_metadata(nil), do: ""

  defp format_metadata(metadata) when is_map(metadata) do
    Jason.encode!(metadata, pretty: true)
  rescue
    _ -> ""
  end

  defp format_metadata(_), do: ""

  # ============================================================================
  # Handlers: Company Details Edit Modal
  # ============================================================================

  defp remove_activity_at(socket, scope, company, current, index) do
    new_activities =
      current
      |> List.delete_at(index)
      |> case do
        [] -> nil
        list -> list
      end

    case Company.update_company(scope, company.id, %{scope_activities: new_activities}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Activity removed.")
         |> assign(:company, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove activity.")}
    end
  end

  defp write_forbidden(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "You do not have permission to change company administration data."
     )}
  end

  # `String.to_integer/1` raises on anything non-numeric, so a forged id crashed
  # the LiveView rather than being refused. Returns nil for junk; callers treat
  # a nil id as "no such address", which is what a forged id is.
  defp parse_index(value, length) do
    case Integer.parse(to_string(value)) do
      {index, ""} when index >= 0 and index < length -> index
      _ -> nil
    end
  end

  # Same shape as `DepartmentsLive`, `RelationshipsLive` and
  # `DepartmentTypesLive`: one clause ahead of the rest, so a write event cannot
  # be added later without deciding whether it belongs on this list. `:if=
  # {@can_update?}` in the template hides the controls, but a hidden control is
  # not a guard -- this route is gated on `admin.company.view`, a read
  # capability, so every one of these was reachable by forging the event.
  @write_events ~w(
    save_details
    add_activity
    remove_activity
    save_metadata
    save_timezone
  )

  @impl true
  def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
      when event in @write_events,
      do: write_forbidden(socket)

  def handle_event("users_filters", params, socket),
    do: apply_table_filters(socket, :users, params)

  def handle_event("employees_filters", params, socket),
    do: apply_table_filters(socket, :employees, params)

  def handle_event("users_sort", %{"sort" => sort_key}, socket),
    do: apply_table_sort(socket, :users, sort_key)

  def handle_event("employees_sort", %{"sort" => sort_key}, socket),
    do: apply_table_sort(socket, :employees, sort_key)

  def handle_event("users_page", %{"page" => page}, socket),
    do: apply_table_page(socket, :users, page)

  def handle_event("employees_page", %{"page" => page}, socket),
    do: apply_table_page(socket, :employees, page)

  def handle_event("edit_details", _params, socket) do
    company = socket.assigns.company

    params = %{
      "name" => company.name,
      "code" => company.code || "",
      "legal_name" => company.legal_name || "",
      "status" => company.status || "active",
      "legal_entity_type_id" => company.legal_entity_type_id,
      "registration_number" => company.registration_number || "",
      "tax_id" => company.tax_id || "",
      "jurisdiction" => company.jurisdiction || "",
      "email" => company.email || "",
      "website" => company.website || "",
      "parent_id" => company.parent_id
    }

    changeset = Company.Schema.update_changeset(company_to_schema(company), params)

    {:noreply,
     socket
     |> assign(:modal_action, :edit_details)
     |> assign(:details_form, to_form(changeset, as: :company))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign(:details_form, nil)}
  end

  def handle_event("validate_details", %{"company" => params}, socket) do
    company = socket.assigns.company

    changeset =
      company_to_schema(company)
      |> Company.Schema.update_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :details_form, to_form(changeset, as: :company))}
  end

  def handle_event("save_details", %{"company" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company = socket.assigns.company

    case Company.update_company(scope, company.id, params) do
      {:ok, updated_company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company details updated successfully.")
         |> assign(:company, updated_company)
         |> assign(:page_title, Company.Summary.display_name(updated_company))
         |> assign(:modal_action, nil)
         |> assign(:details_form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :details_form, to_form(changeset, as: :company))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not update company: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Handlers: Metadata JSON
  # ============================================================================

  def handle_event("edit_metadata", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_metadata?, true)
     |> assign(:metadata_input, format_metadata(socket.assigns.company.metadata))}
  end

  # ============================================================================
  # Handlers: Activities (Tags)
  # ============================================================================

  def handle_event("update_new_activity", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_activity, value)}
  end

  def handle_event("add_activity", %{"activity" => value}, socket) do
    add_activity_internal(socket, value)
  end

  def handle_event("add_activity", _params, socket) do
    add_activity_internal(socket, socket.assigns.new_activity)
  end

  def handle_event("remove_activity", %{"index" => index_str}, socket) do
    scope = socket.assigns.current_scope.scope
    company = socket.assigns.company
    current = company.scope_activities || []

    case parse_index(index_str, length(current)) do
      nil -> {:noreply, socket}
      index -> remove_activity_at(socket, scope, company, current, index)
    end
  end

  def handle_event("cancel_edit_metadata", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_metadata?, false)
     |> assign(:metadata_input, format_metadata(socket.assigns.company.metadata))}
  end

  def handle_event("update_metadata_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :metadata_input, value)}
  end

  def handle_event("save_metadata", %{"metadata" => json_str}, socket) do
    trimmed = String.trim(json_str)
    scope = socket.assigns.current_scope.scope
    company = socket.assigns.company

    if trimmed == "" do
      case Company.update_company(scope, company.id, %{metadata: nil}) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Metadata cleared.")
           |> assign(:company, updated)
           |> assign(:editing_metadata?, false)
           |> assign(:metadata_input, "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to clear metadata.")}
      end
    else
      case Jason.decode(trimmed) do
        {:ok, decoded} when is_map(decoded) ->
          case Company.update_company(scope, company.id, %{metadata: decoded}) do
            {:ok, updated} ->
              {:noreply,
               socket
               |> put_flash(:info, "Metadata saved.")
               |> assign(:company, updated)
               |> assign(:editing_metadata?, false)
               |> assign(:metadata_input, format_metadata(updated.metadata))}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to save metadata.")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Metadata was not saved. Enter valid JSON.")}
      end
    end
  end

  # ============================================================================
  # Handlers: Timezone
  # ============================================================================

  def handle_event("save_timezone", %{"timezone" => tz}, socket) do
    company = socket.assigns.company
    tz = String.trim(to_string(tz))

    scope = SettingsScope.company(company.id, company.tenant_id)

    cond do
      tz == "" ->
        Settings.delete("localization.timezone", scope)

        {:noreply,
         socket
         |> put_flash(:info, "Timezone cleared.")
         |> assign(:company_timezone, "")}

      # The stdlib database is UTC-only; validity means the real IANA
      # database can convert it (#459). A forged value never persists.
      not Bilimbi.Base.DateTime.valid_timezone?(tz) ->
        {:noreply, put_flash(socket, :error, "Choose a valid IANA timezone.")}

      true ->
        save_valid_timezone(socket, scope, tz)
    end
  end

  defp apply_table_filters(socket, kind, params) do
    current = current_table_state(socket, kind)
    filters = Map.get(params, "#{table_param_prefix(kind)}_filters", params)

    search =
      if Map.has_key?(filters, "search"),
        do: normalize_search(filters["search"]),
        else: current.search

    per_page =
      cond do
        Map.has_key?(filters, "perPage") -> normalize_page_size(filters["perPage"])
        Map.has_key?(filters, "per_page") -> normalize_page_size(filters["per_page"])
        true -> current.per_page
      end

    state =
      put_table_state(socket.assigns.table_state, kind, %{
        current
        | search: search,
          per_page: per_page,
          page: @default_page
      })

    {:noreply, push_patch(socket, to: company_show_path(socket, state))}
  end

  defp apply_table_sort(socket, kind, sort_key) do
    state =
      socket.assigns.table_state
      |> put_table_state(kind, next_table_sort(current_table_state(socket, kind), kind, sort_key))

    {:noreply, push_patch(socket, to: company_show_path(socket, state))}
  end

  defp apply_table_page(socket, kind, page) do
    current = current_table_state(socket, kind)
    target_page = normalize_page(page)
    state = put_table_state(socket.assigns.table_state, kind, %{current | page: target_page})

    {:noreply, push_patch(socket, to: company_show_path(socket, state))}
  end

  defp refresh_show_table_pages(socket) do
    table_state = socket.assigns.table_state || default_table_state()

    # Users and Employees are both core-owned discovered embeds now; the page
    # only tracks their URL table-state and hands it to the panels, which do
    # their own listing (#595).
    socket
    |> assign(:users_table_state, table_state.users)
    |> assign(:employees_table_state, table_state.employees)
  end

  defp default_table_state, do: @table_defaults

  defp table_state_from_params(params) do
    [:users, :employees]
    |> Map.new(fn kind ->
      prefix = table_param_prefix(kind)
      default = Map.fetch!(@table_defaults, kind)

      {kind,
       %{
         search: normalize_search(params["#{prefix}_search"]),
         sort_by: normalize_sort_by(kind, params["#{prefix}_sort"]),
         sort_dir: normalize_sort_dir(params["#{prefix}_dir"], default.sort_dir),
         page: normalize_page(params["#{prefix}_page"]),
         per_page:
           normalize_page_size(params["#{prefix}_per_page"] || params["#{prefix}_perPage"])
       }}
    end)
  end

  defp current_table_state(socket, kind),
    do:
      Map.get(
        socket.assigns.table_state || default_table_state(),
        kind,
        Map.fetch!(@table_defaults, kind)
      )

  defp put_table_state(table_state, kind, state), do: Map.put(table_state, kind, state)

  defp next_table_sort(current, kind, sort_key) do
    sort_by = normalize_sort_by(kind, sort_key)

    if current.sort_by == sort_by do
      %{current | sort_dir: toggle_sort_dir(current.sort_dir), page: @default_page}
    else
      %{current | sort_by: sort_by, sort_dir: :asc, page: @default_page}
    end
  end

  defp toggle_sort_dir(:asc), do: :desc
  defp toggle_sort_dir(:desc), do: :asc
  defp toggle_sort_dir(_dir), do: :asc

  defp normalize_search(nil), do: nil

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_sort_by(kind, nil), do: Map.fetch!(@table_defaults, kind).sort_by

  defp normalize_sort_by(kind, value) when is_binary(value) do
    sort = value |> String.trim() |> String.downcase()

    if sort in Map.fetch!(@table_sorts, kind),
      do: sort,
      else: Map.fetch!(@table_defaults, kind).sort_by
  end

  defp normalize_sort_by(kind, _value), do: Map.fetch!(@table_defaults, kind).sort_by

  defp normalize_sort_dir(nil, default), do: default

  defp normalize_sort_dir(value, default) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "desc" -> :desc
      "asc" -> :asc
      _ -> default
    end
  end

  defp normalize_sort_dir(_value, default), do: default

  defp normalize_page(value) do
    case positive_integer(value) do
      page when is_integer(page) -> page
      _ -> @default_page
    end
  end

  defp normalize_page_size(value) do
    case positive_integer(value) do
      size when size in @page_sizes -> size
      _ -> @default_page_size
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp company_show_path(socket, table_state) do
    company = socket.assigns.company

    params =
      [:users, :employees]
      |> Enum.reduce([], fn kind, acc -> acc ++ table_query_params(kind, table_state[kind]) end)

    case params do
      [] -> ~p"/companies/#{company.id}"
      _ -> ~p"/companies/#{company.id}?#{params}"
    end
  end

  defp table_query_params(kind, state) do
    default = Map.fetch!(@table_defaults, kind)
    prefix = table_param_prefix(kind)

    []
    |> maybe_put_param("#{prefix}_search", state.search)
    |> maybe_put_param("#{prefix}_sort", state.sort_by != default.sort_by && state.sort_by)
    |> maybe_put_param("#{prefix}_dir", state.sort_dir != default.sort_dir && state.sort_dir)
    |> maybe_put_param("#{prefix}_page", state.page != @default_page && state.page)
    |> maybe_put_param(
      "#{prefix}_per_page",
      state.per_page != @default_page_size && state.per_page
    )
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, false), do: params
  defp maybe_put_param(params, key, value), do: params ++ [{key, value}]

  defp table_param_prefix(:users), do: "users"
  defp table_param_prefix(:employees), do: "employees"

  # ============================================================================
  # Helpers: Activities, Forms and Autocompletion
  # ============================================================================

  defp save_valid_timezone(socket, scope, tz) do
    case Settings.put("localization.timezone", tz, scope) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Timezone saved: #{tz}")
         |> assign(:company_timezone, tz)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save timezone.")}
    end
  end

  defp add_activity_internal(socket, raw_activity) do
    activity = String.trim(to_string(raw_activity))

    if activity == "" do
      {:noreply, socket}
    else
      scope = socket.assigns.current_scope.scope
      company = socket.assigns.company
      current = company.scope_activities || []
      new_activities = Enum.uniq(current ++ [activity])

      case Company.update_company(scope, company.id, %{scope_activities: new_activities}) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Activity added.")
           |> assign(:company, updated)
           |> assign(:new_activity, "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to add activity.")}
      end
    end
  end

  defp country_options(countries),
    do: Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})

  defp legal_entity_type_options(types), do: Enum.map(types, &{&1.name, &1.id})

  defp parent_company_options(companies), do: Enum.map(companies, &{&1.name, &1.id})

  defp legal_entity_type_name(nil, _types), do: nil

  defp legal_entity_type_name(id, types) do
    case Enum.find(types, &(&1.id == id)) do
      nil -> nil
      type -> type.name
    end
  end

  defp country_name(nil, _countries), do: nil

  defp country_name(iso, countries) do
    case Enum.find(countries, &(&1.iso == iso)) do
      nil -> iso
      country -> "#{country.country} (#{country.iso})"
    end
  end

  defp parent_name(nil, _parents), do: nil

  defp parent_name(parent_id, parents) do
    case Enum.find(parents, &(&1.id == parent_id)) do
      nil -> nil
      parent -> parent.name
    end
  end

  defp company_to_schema(%Company.Summary{} = company) do
    %Company.Schema{
      id: company.id,
      tenant_id: company.tenant_id,
      name: company.name,
      code: company.code,
      status: company.status,
      legal_name: company.legal_name,
      registration_number: company.registration_number,
      tax_id: company.tax_id,
      legal_entity_type_id: company.legal_entity_type_id,
      jurisdiction: company.jurisdiction,
      email: company.email,
      website: company.website,
      parent_id: company.parent_id,
      scope_activities: company.scope_activities,
      metadata: company.metadata
    }
  end

  # ============================================================================
  # Template
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {@company.name}
          <:subtitle>
            <%!-- Belimbing: title=name, subtitle=legal_name. Repeating the
                 name when no distinct legal name exists says nothing, so the
                 code stands in (#622). --%>
            {if @company.legal_name && @company.legal_name != @company.name,
              do: @company.legal_name,
              else: @company.code}
          </:subtitle>
          <:actions>
            <.badge kind={
              case @company.status do
                "active" -> :success
                "suspended" -> :danger
                "pending" -> :warning
                _ -> :neutral
              end
            }>
              {String.capitalize(@company.status)}
            </.badge>
            <.button
              navigate={~p"/companies/#{@company.id}/departments"}
              class="text-xs"
            >
              Departments
            </.button>
            <.button
              navigate={~p"/companies/#{@company.id}/relationships"}
              class="text-xs"
            >
              Relationships
            </.button>
            <.button id="company-back" navigate={~p"/companies"}>
              Back to companies
            </.button>
          </:actions>
        </.header>

        <.alert :if={@is_primary} kind={:info} class="mt-4">
          This is the primary company representing its tenant.
        </.alert>

        <%!-- Section 1: Company Details --%>
        <.card id="company-details-card" class="mt-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Company Details
            </h3>
            <.button
              :if={@can_update?}
              id="edit-company-details-btn"
              phx-click="edit_details"
              class="text-xs"
            >
              Edit Details
            </.button>
          </div>

          <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Name</dt>
              <dd id="detail-name" class="mt-1 text-sm font-semibold text-ink-strong">
                {@company.name}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Code</dt>
              <dd id="detail-code" class="mt-1 text-sm font-mono text-ink">
                {@company.code || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Legal Name</dt>
              <dd id="detail-legal-name" class="mt-1 text-sm text-ink">
                {@company.legal_name || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Status</dt>
              <dd id="detail-status" class="mt-1">
                <.badge kind={
                  case @company.status do
                    "active" -> :success
                    "suspended" -> :danger
                    "pending" -> :warning
                    _ -> :neutral
                  end
                }>
                  {String.capitalize(@company.status)}
                </.badge>
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Legal Entity Type</dt>
              <dd id="detail-legal-entity-type" class="mt-1 text-sm text-ink">
                {legal_entity_type_name(@company.legal_entity_type_id, @legal_entity_types) || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Registration Number</dt>
              <dd id="detail-registration-number" class="mt-1 text-sm text-ink">
                {@company.registration_number || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Tax ID</dt>
              <dd id="detail-tax-id" class="mt-1 text-sm text-ink">
                {@company.tax_id || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Jurisdiction</dt>
              <dd id="detail-jurisdiction" class="mt-1 text-sm text-ink">
                {country_name(@company.jurisdiction, @countries) || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Email</dt>
              <dd id="detail-email" class="mt-1 text-sm text-ink">
                {@company.email || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-ink-subtle">Website</dt>
              <dd id="detail-website" class="mt-1 text-sm text-ink">
                <a
                  :if={@company.website}
                  href={@company.website}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-action hover:underline"
                >
                  {@company.website}
                </a>
                <span :if={!@company.website}>—</span>
              </dd>
            </div>
            <div class="sm:col-span-2">
              <dt class="text-xs font-medium text-ink-subtle">Parent Company</dt>
              <dd id="detail-parent" class="mt-1 text-sm text-ink">
                {parent_name(@company.parent_id, @parent_companies) || "None"}
              </dd>
            </div>
          </dl>

          <%!-- Business Activities Tags --%>
          <div id="scope-activities-section" class="mt-6 border-t border-line pt-4">
            <dt class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Business Activities
            </dt>
            <p class="mt-0.5 text-xs text-ink-subtle">
              Industry, services, and business focus areas of this company.
            </p>
            <div class="mt-2 flex flex-wrap items-center gap-2">
              <%= for {activity, idx} <- Enum.with_index(@company.scope_activities || []) do %>
                <span class="inline-flex items-center gap-1 rounded-full border border-line bg-surface-sunken px-3 py-1 text-xs font-medium text-ink">
                  {activity}
                  <button
                    :if={@can_update?}
                    type="button"
                    phx-click="remove_activity"
                    phx-value-index={idx}
                    class="text-ink-subtle hover:text-danger"
                    title="Remove"
                  >
                    &times;
                  </button>
                </span>
              <% end %>
              <span :if={is_nil(@company.scope_activities) or @company.scope_activities == []} class="text-sm text-ink-subtle">
                —
              </span>
            </div>

            <form
              :if={@can_update?}
              id="add-activity-form"
              phx-submit="add_activity"
              class="mt-3 flex items-center gap-2"
            >
              <input
                type="text"
                name="activity"
                id="company-new-activity"
                value={@new_activity}
                phx-change="update_new_activity"
                placeholder="e.g. manufacturing"
                class="w-64 rounded-xl border border-line px-3 py-1.5 text-sm bg-surface text-ink placeholder:text-ink-subtle focus:outline-none focus:ring-1 focus:ring-action"
              />
              <.button type="submit" class="text-xs">
                Add activity
              </.button>
            </form>
          </div>

          <%!-- Metadata JSON --%>
          <div class="mt-6 border-t border-line pt-4">
            <div class="flex items-center justify-between">
              <dt class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
                Metadata
              </dt>
              <button
                :if={@can_update? and not @editing_metadata?}
                type="button"
                id="edit-metadata-btn"
                phx-click="edit_metadata"
                class="text-xs text-action hover:underline"
              >
                Edit Metadata
              </button>
            </div>

            <div :if={not @editing_metadata?} class="mt-2">
              <%= if @company.metadata do %>
                <pre id="company-metadata-display" class="overflow-x-auto rounded-xl bg-surface-sunken p-3 text-xs font-mono text-ink">{format_metadata(@company.metadata)}</pre>
              <% else %>
                <span class="text-sm text-ink-subtle">—</span>
              <% end %>
            </div>

            <form
              :if={@editing_metadata?}
              id="metadata-form"
              phx-submit="save_metadata"
              class="mt-2 space-y-2"
            >
              <textarea
                name="metadata"
                id="company-metadata-json"
                rows="5"
                class="w-full rounded-xl border border-line bg-surface p-3 text-xs font-mono text-ink focus:outline-none focus:ring-1 focus:ring-action"
                placeholder='{"employee_count": 120, "founded_year": 2014}'
              >{@metadata_input}</textarea>
              <div class="flex items-center gap-2">
                <.button type="submit" variant="primary" class="text-xs">
                  Save Metadata
                </.button>
                <.button type="button" phx-click="cancel_edit_metadata" class="text-xs">
                  Cancel
                </.button>
              </div>
            </form>
          </div>
        </.card>

        <%!-- Section 2: Addresses — core/address-owned discovered embed (#595).
             Core Address can depend on Core Company but not the reverse, so the
             company page renders the panel by manifest key rather than probing.
             The former inline section (attach/create/detach/update plus the
             Geonames create cascade) now lives entirely in the panel. --%>
        <.discovered_panel
          key="company.addresses"
          id="company-addresses-panel"
          current_scope={@current_scope}
          opts={%{company_id: @company.id}}
        />

        <%!-- Section 3: Timezone Settings --%>
        <.card id="company-timezone-card" class="mt-6">
          <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle mb-3">
            Timezone
          </h3>
          <form id="company-timezone-form" phx-change="save_timezone" class="max-w-md space-y-2">
            <.input
              type="select"
              id="company-timezone-select"
              name="timezone"
              value={@company_timezone}
              prompt="Not configured (UTC)"
              options={@timezone_options}
              label="Company Default Timezone"
              hint="Default timezone for this company. Used when displaying dates and times in Company mode."
            />
          </form>
          <div :if={@company_timezone == ""} class="mt-2">
            <.alert kind={:info}>
              No timezone is configured for this company. Dates and times will display in UTC until a timezone is set.
            </.alert>
          </div>
        </.card>

        <%!-- Section 4: Subsidiaries (Child Companies) --%>
        <.card :if={@children != []} id="company-subsidiaries-card" class="mt-6">
          <div class="flex items-center gap-2 mb-4">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              Subsidiaries
            </h3>
            <.badge>{length(@children)}</.badge>
          </div>

          <.table
            id="company-subsidiaries-table"
            rows={@children}
            row_id={fn child -> "child-company-#{child.id}" end}
            row_item={fn child -> child end}
            caption="Subsidiaries"
          >
            <:col :let={child} label="Name">
              <.link navigate={~p"/companies/#{child.id}"} class="font-medium text-action hover:underline">
                {child.name}
              </.link>
            </:col>
            <:col :let={child} label="Status">
              <.badge kind={
                case child.status do
                  "active" -> :success
                  "suspended" -> :danger
                  "pending" -> :warning
                  _ -> :neutral
                end
              }>
                {String.capitalize(child.status)}
              </.badge>
            </:col>
            <:col :let={child} label="Legal Entity Type">
              <span class="text-sm text-ink-subtle">
                {legal_entity_type_name(child.legal_entity_type_id, @legal_entity_types) || "—"}
              </span>
            </:col>
            <:col :let={child} label="Jurisdiction">
              <span class="text-sm text-ink-subtle">
                {child.jurisdiction || "—"}
              </span>
            </:col>
          </.table>
        </.card>

        <%!-- Section 5: Departments --%>
        <.card id="company-departments-card" class="mt-6">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
                Departments
              </h3>
              <.badge>{length(@departments)}</.badge>
            </div>
            <.button
              navigate={~p"/companies/#{@company.id}/departments"}
              class="text-xs"
            >
              Manage
            </.button>
          </div>

          <.table
            id="company-departments-table"
            rows={@departments}
            row_id={fn dept -> "department-#{dept.id}" end}
            row_item={fn dept -> dept end}
            caption="Departments"
          >
            <:col :let={dept} label="Department Type">
              <span class="font-medium text-ink-strong">{dept.type.name}</span>
            </:col>
            <:col :let={dept} label="Category">
              <span class="text-sm text-ink-subtle">{dept.type.category || "—"}</span>
            </:col>
            <:col :let={dept} label="Head">
              <span class="text-sm text-ink-subtle">
                {@department_head_names[dept.head_id] || "—"}
              </span>
            </:col>
            <:col :let={dept} label="Status">
              <.badge kind={if dept.status == "active", do: :success, else: :warning}>
                {String.capitalize(dept.status)}
              </.badge>
            </:col>
            <:empty :if={@departments == []}>
              No departments configured.
            </:empty>
          </.table>
        </.card>

        <%!-- Section 6: Relationships --%>
        <.card id="company-relationships-card" class="mt-6">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
                Relationships
              </h3>
              <.badge>{length(@relationships)}</.badge>
            </div>
            <.button
              navigate={~p"/companies/#{@company.id}/relationships"}
              class="text-xs"
            >
              Manage
            </.button>
          </div>

          <.table
            id="company-relationships-table"
            rows={@relationships}
            row_id={fn rel -> "rel-#{rel.id}" end}
            row_item={fn rel -> rel end}
            caption="Relationships"
          >
            <:col :let={rel} label="Company">
              <.link navigate={~p"/companies/#{rel.other_company.id}"} class="font-medium text-action hover:underline">
                {rel.other_company.name}
              </.link>
            </:col>
            <:col :let={rel} label="Relationship Type">
              <span class="text-sm text-ink">{rel.type.name}</span>
            </:col>
            <:col :let={rel} label="Direction">
              <.badge kind={:neutral}>
                {if rel.direction == :outgoing, do: "Outgoing", else: "Incoming"}
              </.badge>
            </:col>
            <:col :let={rel} label="Effective">
              <span class="text-xs tabular-nums text-ink-subtle">
                {rel.effective_from || "Always"} → {rel.effective_to || "Present"}
              </span>
            </:col>
            <:col :let={rel} label="Status">
              <.badge kind={if rel.is_active, do: :success, else: :neutral}>
                {if rel.is_active, do: "Active", else: "Inactive"}
              </.badge>
            </:col>
            <:empty :if={@relationships == []}>
              No relationships defined.
            </:empty>
          </.table>
        </.card>

        <%!-- Section 7: External Accesses --%>
        <%!-- Rendered unconditionally with an empty state, as Belimbing does
             (`show.blade.php:259` has no `@if`, unlike the Subsidiaries card
             above it at `:41`, which is guarded and matches here). A card that
             disappears when empty reads as "this company cannot have external
             access" rather than "it has none". --%>
        <.card id="company-external-accesses-card" class="mt-6">
          <div class="flex items-center gap-2 mb-4">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink-subtle">
              External Accesses
            </h3>
            <.badge>{length(@external_accesses)}</.badge>
          </div>

          <.table
            id="company-external-accesses-table"
            rows={@external_accesses}
            row_id={fn access -> "access-#{access.id}" end}
            row_item={fn access -> access end}
            caption="External Accesses"
          >
            <:col :let={access} label="User">
              <%= if user = @external_access_users[access.user_id] do %>
                <.link navigate={~p"/users/#{access.user_id}"} class="font-medium text-action hover:underline">
                  {user.name}
                </.link>
              <% else %>
                <span class="text-ink-subtle">—</span>
              <% end %>
            </:col>
            <:col :let={access} label="Permissions">
              <div :if={is_list(access.permissions) and access.permissions != []} class="flex flex-wrap gap-1">
                <.badge :for={permission <- access.permissions}>{permission}</.badge>
              </div>
              <span :if={not (is_list(access.permissions) and access.permissions != [])} class="text-ink-subtle">
                —
              </span>
            </:col>
            <:col :let={access} label="Status">
              <.badge kind={if access.is_active, do: :success, else: :danger}>
                {if access.is_active, do: "Active", else: "Inactive"}
              </.badge>
            </:col>
            <:col :let={access} label="Granted At">
              <span class="tabular-nums text-xs text-ink-subtle">{access.access_granted_at || "—"}</span>
            </:col>
            <:col :let={access} label="Expires At">
              <span class="tabular-nums text-xs text-ink-subtle">{access.access_expires_at || "—"}</span>
            </:col>

            <:empty :if={@external_accesses == []}>
              No external accesses.
            </:empty>
          </.table>
        </.card>

        <%!-- Section 8: Users — core/user-owned discovered embed (#595). Core User
             can depend on Core Company but not the reverse, so the company page
             renders the panel by manifest key rather than probing. --%>
        <.discovered_panel
          key="company.users"
          id="company-users-panel"
          current_scope={@current_scope}
          opts={%{company_id: @company.id, table_state: @users_table_state, page_sizes: @page_sizes}}
        />

        <%!-- Section 9: Employees — core/employee-owned discovered embed (#595).
             Core Employee can depend on Core Company but not the reverse, so the
             company page renders the panel by manifest key rather than probing
             or declaring an edge that would cycle. --%>
        <.discovered_panel
          key="company.employees"
          id="company-employees-panel"
          current_scope={@current_scope}
          opts={%{company_id: @company.id, table_state: @employees_table_state, page_sizes: @page_sizes}}
        />

        <%!-- MODAL 1: Edit Company Details --%>
        <div
          :if={@modal_action == :edit_details}
          id="company-details-modal"
          class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-ink/40 p-4"
        >
          <div class="w-full max-w-2xl rounded-2xl border border-line bg-surface p-6 shadow-xl">
            <h3 class="text-base font-semibold text-ink-strong mb-4">
              Edit Company Details
            </h3>

            <.form
              for={@details_form}
              id="company-details-form"
              phx-change="validate_details"
              phx-submit="save_details"
              class="space-y-4"
            >
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@details_form[:name]}
                  id="company-name-input"
                  label="Name"
                  required
                />
                <.input
                  field={@details_form[:code]}
                  id="company-code-input"
                  label="Code"
                />
              </div>

              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@details_form[:legal_name]}
                  id="company-legal-name-input"
                  label="Legal Name"
                />
                <.input
                  type="select"
                  field={@details_form[:status]}
                  id="company-status-select"
                  label="Status"
                  options={[
                    {"Active", "active"},
                    {"Suspended", "suspended"},
                    {"Pending", "pending"},
                    {"Archived", "archived"}
                  ]}
                />
              </div>

              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  type="select"
                  field={@details_form[:legal_entity_type_id]}
                  id="company-legal-entity-type-select"
                  label="Legal Entity Type"
                  prompt="None"
                  options={legal_entity_type_options(@legal_entity_types)}
                />
                <.input
                  type="select"
                  field={@details_form[:jurisdiction]}
                  id="company-jurisdiction-select"
                  label="Jurisdiction"
                  prompt="None"
                  options={country_options(@countries)}
                />
              </div>

              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@details_form[:registration_number]}
                  id="company-registration-number-input"
                  label="Registration Number"
                />
                <.input
                  field={@details_form[:tax_id]}
                  id="company-tax-id-input"
                  label="Tax ID"
                />
              </div>

              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@details_form[:email]}
                  id="company-email-input"
                  type="email"
                  label="Email"
                />
                <.input
                  field={@details_form[:website]}
                  id="company-website-input"
                  type="url"
                  label="Website"
                />
              </div>

              <div>
                <.input
                  type="select"
                  field={@details_form[:parent_id]}
                  id="company-parent-select"
                  label="Parent Company"
                  prompt="None"
                  options={parent_company_options(@parent_companies)}
                />
              </div>

              <div class="flex items-center justify-end gap-3 pt-4 border-t border-line">
                <.button type="button" phx-click="close_modal">
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  Save Changes
                </.button>
              </div>
            </.form>
          </div>
        </div>

      </.page>
    </Layouts.app>
    """
  end
end
