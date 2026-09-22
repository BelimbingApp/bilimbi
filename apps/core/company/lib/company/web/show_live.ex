defmodule Bilimbi.Core.Company.Web.ShowLive do
  @moduledoc """
  Read-first company profile: identity, addresses, timezone, subsidiaries,
  departments, relationships, external accesses, users, and employees — all
  accessed through declared public domain APIs.

  The page shows the company as facts. An operator holding
  `admin.company.update` edits each fact in place and a committed edit saves
  by itself; there is no edit mode, no "Edit Details" button and no modal, as
  Belimbing's `admin/companies/show` edits the same facts in place:

  - a text fact (name, code, legal name, registration number, tax ID, email,
    website) commits on Enter or on leaving the field, through
    `<.inline_edit>`; Escape cancels. Name and code are required columns, so
    an emptied value commits nothing; the other five are nullable and pass
    `allow_empty`;
  - a choice fact (status, legal entity type, jurisdiction, parent company,
    default timezone) reads as its badge or name and becomes a select on
    click; the select commits on change, and Escape or leaving it cancels.
    The default timezone reads the company's own setting; without one it
    reads "Not configured" beside the zone `Bilimbi.Base.DateTime` renders
    its dates in through the tenant and platform settings, so UTC is named
    only when that resolution ends at UTC or the stored zone is
    unconvertible;
  - a business activity is added through the same in-place text control:
    its "Add activity" trigger opens an input that commits on Enter or on
    leaving it, as Belimbing's "+ Add" chip does, and an activity is removed
    from its chip;
  - the metadata JSON is a multi-line document, which Enter cannot commit, so
    it is the one fact with an explicit Apply: the demoted pencil beside the
    value opens a textarea with Apply and Cancel, and Escape cancels.

  Each fact reports its own outcome through the shared commit status that
  `Bilimbi.Base.UI.CommitStatus` keeps: "Saving…" while the round trip is in
  flight, "Saved" once stored, and an alert on the fact naming the rejected
  value and the reason when the save was refused. The stored value stays on
  screen until the server confirms a change, and success does not flash. A
  viewer without `admin.company.update` sees every fact with no editor, and
  every write re-asks Authz before it lands.

  The header's actions row carries the record's status, record history as the
  demoted labelled action — the registry's `history` clock beside the visible
  word "History" — and a plain "← Back" link, and no button; the title row
  keeps the pin icon action. The Departments and Relationships
  workflows are reached through the demoted "Manage" link on the section that
  lists them, carrying the registry's `manage` glyph, which is the cog
  Belimbing uses for the same action.

  Every section below the header is a `<.card>` opened by the shared
  `<.section_heading>` — the one heading treatment a detail page has — and
  the Company Details facts are the shared `<.list>`, with Business
  Activities and Metadata as rows of that same list, as Belimbing's
  company-details partial keeps them. Section tables sit unframed inside
  their card. Subsidiaries, departments, relationships and external accesses
  are relations with workflows of their own, and whether the company is its
  tenant's primary company is Core Company's own assignment, so those stay
  read-only here.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.PrincipalDirectory
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.UI.CommitStatus
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Geonames

  @update_capability "admin.company.update"

  # The facts an inline text edit may write, keyed by the form name the hook
  # pushes. A name outside this map is ignored; user input never becomes an
  # atom.
  @inline_fields %{
    "name" => :name,
    "code" => :code,
    "legal_name" => :legal_name,
    "registration_number" => :registration_number,
    "tax_id" => :tax_id,
    "email" => :email,
    "website" => :website
  }

  # Name and code are required columns; an emptied value of any other text
  # fact is a real edit.
  @nullable_inline_facts ~w(legal_name registration_number tax_id email website)

  # The choice facts a select commits on change, keyed the same way. The
  # default timezone is a company setting rather than a column, so it is a
  # choice fact with its own event.
  @choice_fields %{
    "status" => :status,
    "legal_entity_type_id" => :legal_entity_type_id,
    "jurisdiction" => :jurisdiction,
    "parent_id" => :parent_id
  }

  @choice_facts Map.keys(@choice_fields) ++ ["timezone"]

  @fact_labels %{
    "name" => "Name",
    "code" => "Code",
    "legal_name" => "Legal Name",
    "status" => "Status",
    "legal_entity_type_id" => "Legal Entity Type",
    "registration_number" => "Registration Number",
    "tax_id" => "Tax ID",
    "jurisdiction" => "Jurisdiction",
    "email" => "Email",
    "website" => "Website",
    "parent_id" => "Parent Company",
    "activities" => "Business Activities",
    "metadata" => "Metadata",
    "timezone" => "Default Timezone"
  }

  @status_options [
    {"Active", "active"},
    {"Suspended", "suspended"},
    {"Pending", "pending"},
    {"Archived", "archived"}
  ]

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
        external_access_names = resolve_external_access_names(scope, external_accesses)

        {:ok,
         socket
         |> assign(:page_title, Company.Summary.display_name(company))
         |> assign(:active_nav, "admin.company")
         |> assign(:company, company)
         |> assign(:is_primary, is_primary)
         |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
         |> assign(:legal_entity_types, legal_entity_types)
         |> assign(:countries, countries)
         |> assign(:parent_companies, parent_companies)
         |> assign(:children, children)
         |> assign(:departments, departments)
         |> assign(:department_head_names, department_head_names)
         |> assign(:relationships, relationships)
         |> assign(:external_accesses, external_accesses)
         |> assign(:external_access_names, external_access_names)
         |> assign(:page_sizes, @page_sizes)
         |> assign(:table_state, default_table_state())
         |> assign_timezone(company)
         |> assign(:status_options, @status_options)
         |> CommitStatus.init()
         |> assign(:editing_field, nil)
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

  # The company's own explicit setting, as Belimbing's
  # `explicitCompanyTimezone` reads it, decides whether the company has
  # configured a timezone; the zone its dates display in is the one
  # `Bilimbi.Base.DateTime` renders them in, company then tenant then platform
  # default, UTC for an unconvertible value. An unset company under a
  # tenant-level zone reads "Not configured (<that zone>)", never UTC.
  defp assign_timezone(socket, company) do
    scope = SettingsScope.company(company.id, company.tenant_id)

    explicit =
      if Settings.overridden?("localization.timezone", scope),
        do: Settings.get("localization.timezone", scope),
        else: ""

    socket
    |> assign(:company_timezone, explicit)
    |> assign(:resolved_timezone, Bilimbi.Base.DateTime.company_timezone(scope))
  end

  # ============================================================================
  # Naming siblings across the module boundary
  #
  # This file reaches no sibling Core module by runtime probe (#595, #669).
  # Geonames is a declared dependency, called directly for the jurisdiction
  # label. Employees, addresses and users render through their owners' discovered
  # embeds ("company.employees" / "company.addresses" / "company.users"). The one
  # remaining cross-boundary need — naming the user an external-access grant
  # points at — goes through base/principal_directory, the same seam the
  # department Head column uses for `{:employee, id}` (ADR 0011/0014).
  # ============================================================================

  # An external-access grant names a user, which core/company cannot reach across
  # the module boundary. base/principal_directory resolves the `{:user, id}`
  # identities through the user-owned provider, so this file names grantees
  # without depending on core/user. Returns a user_id => name map; a grant to a
  # deleted or unresolvable user is simply absent and falls back to the em dash in
  # the table — which is exactly what an operator needs to see.
  defp resolve_external_access_names(scope, external_accesses) do
    candidates =
      external_accesses
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{:user, &1})

    with [_ | _] <- candidates,
         {:ok, named} <- PrincipalDirectory.rank(scope, candidates) do
      Map.new(named, fn %{id: id, name: name} -> {id, name} end)
    else
      _ -> %{}
    end
  end

  # Geonames is a declared company dependency (bilimbi.module.exs). Call it
  # directly — the same pattern create_live.ex already uses. Do not probe.
  defp list_geonames_countries, do: Geonames.list_countries()

  defp company_auditable_types do
    ["Bilimbi.Core.Company.Schema", "Bilimbi.Core.Company", Company.addressable_identity()]
  end

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
  # Handlers: In-place Facts
  # ============================================================================

  # `String.to_integer/1` raises on anything non-numeric, so a forged id crashed
  # the LiveView rather than being refused. Returns nil for junk; callers treat
  # a nil index as "no such activity", which is what a forged index is.
  defp parse_index(value, length) do
    case Integer.parse(to_string(value)) do
      {index, ""} when index >= 0 and index < length -> index
      _ -> nil
    end
  end

  # One gate ahead of every persisting event, in the shape `DepartmentsLive`,
  # `RelationshipsLive` and `DepartmentTypesLive` share: `:if={@can_update?}`
  # in the template hides the controls, but a hidden control is not a guard --
  # this route is gated on `admin.company.view`, a read capability, so each
  # of these is reachable by forging the event. The gate re-asks Authz on
  # every write, so a grant revoked while the page is open is refused too,
  # and a write event cannot be added later without deciding whether it
  # belongs on this list.
  @write_events ~w(
    save_field
    edit_field
    save_choice
    add_activity
    remove_activity
    edit_metadata
    save_metadata
    save_timezone
  )

  @impl true
  def handle_event(event, params, socket) when event in @write_events do
    if can_update?(socket) do
      write_event(event, params, socket)
    else
      {:noreply, write_forbidden(socket)}
    end
  end

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end

  def handle_event("cancel_edit_metadata", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_metadata?, false)
     |> assign(:metadata_input, format_metadata(socket.assigns.company.metadata))}
  end

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

  # A text fact: the hook pushes `%{"id" => _, <name> => value}`, and only a
  # declared name is written.
  defp write_event("save_field", params, socket) do
    case CommitStatus.inline_field(params, @inline_fields) do
      {:ok, name, field, value} ->
        {:noreply, save_fact(socket, name, %{field => normalize_param(value)}, value)}

      :error ->
        {:noreply, socket}
    end
  end

  # A choice fact: the read state opens the select, which commits on change.
  defp write_event("edit_field", %{"field" => field}, socket) when field in @choice_facts do
    {:noreply, assign(socket, :editing_field, field)}
  end

  defp write_event("edit_field", _params, socket), do: {:noreply, socket}

  defp write_event("save_choice", params, socket) do
    socket = assign(socket, :editing_field, nil)

    case CommitStatus.inline_field(params, @choice_fields) do
      {:ok, name, field, value} ->
        attrs = %{field => normalize_param(value)}
        {:noreply, save_fact(socket, name, attrs, choice_label(socket, name, value))}

      :error ->
        {:noreply, socket}
    end
  end

  # The activities fact: adding appends the committed text, removing drops
  # the chip's index, and both report on the fact. Belimbing keeps the list
  # unique and stores an emptied list as null; so does this.
  defp write_event("add_activity", %{"activity" => raw}, socket) when is_binary(raw) do
    activity = String.trim(raw)
    current = socket.assigns.company.scope_activities || []

    if activity == "" do
      {:noreply, socket}
    else
      attrs = %{scope_activities: Enum.uniq(current ++ [activity])}
      {:noreply, save_fact(socket, "activities", attrs, activity)}
    end
  end

  defp write_event("add_activity", _params, socket), do: {:noreply, socket}

  defp write_event("remove_activity", %{"index" => index_param}, socket) do
    current = socket.assigns.company.scope_activities || []

    case parse_index(index_param, length(current)) do
      nil ->
        {:noreply, socket}

      index ->
        {removed, remaining} = List.pop_at(current, index)
        attrs = %{scope_activities: if(remaining == [], do: nil, else: remaining)}
        {:noreply, save_fact(socket, "activities", attrs, removed)}
    end
  end

  defp write_event("remove_activity", _params, socket), do: {:noreply, socket}

  # The metadata fact: a JSON document edited in a textarea with an explicit
  # Apply. A refusal keeps the editor open with what was typed, so the
  # operator corrects it where they typed it.
  defp write_event("edit_metadata", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_metadata?, true)
     |> assign(:metadata_input, format_metadata(socket.assigns.company.metadata))}
  end

  defp write_event("save_metadata", %{"metadata" => json}, socket) when is_binary(json) do
    trimmed = String.trim(json)

    # The reply patch re-renders the textarea, so what was typed has to be
    # the assign's value or a refusal would hand the operator the stored
    # document back instead of the text to correct.
    socket = assign(socket, :metadata_input, json)

    with {:ok, metadata} <- decode_metadata(trimmed),
         {:ok, socket} <- commit_company(socket, "metadata", %{metadata: metadata}, trimmed) do
      {:noreply,
       socket
       |> assign(:editing_metadata?, false)
       |> assign(:metadata_input, format_metadata(socket.assigns.company.metadata))
       |> CommitStatus.put("metadata", :saved)}
    else
      {:error, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, socket}

      :invalid ->
        rejected = CommitStatus.rejected_value(trimmed)

        {:noreply,
         CommitStatus.put(
           socket,
           "metadata",
           {:error, "#{inspect(rejected)} was not saved: Metadata must be a JSON object."}
         )}
    end
  end

  defp write_event("save_metadata", _params, socket), do: {:noreply, socket}

  # The default timezone is a company setting, not a column: it commits
  # through Base Settings and reports on its own fact like the rest.
  defp write_event("save_timezone", params, socket) do
    socket = assign(socket, :editing_field, nil)
    tz = params |> Map.get("timezone", "") |> to_string() |> String.trim()
    company = socket.assigns.company
    settings_scope = SettingsScope.company(company.id, company.tenant_id)

    cond do
      tz == "" ->
        Settings.delete("localization.timezone", settings_scope)

        {:noreply,
         socket
         |> assign_timezone(company)
         |> CommitStatus.put("timezone", :saved)}

      # The stdlib database is UTC-only; validity means the real IANA
      # database can convert it (#459). A forged value never persists.
      not Bilimbi.Base.DateTime.valid_timezone?(tz) ->
        rejected = CommitStatus.rejected_value(tz)

        {:noreply,
         CommitStatus.put(
           socket,
           "timezone",
           {:error,
            "#{inspect(rejected)} was not saved: #{fact_label("timezone")} must be a valid IANA timezone."}
         )}

      true ->
        case Settings.put("localization.timezone", tz, settings_scope) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign_timezone(company)
             |> CommitStatus.put("timezone", :saved)}

          {:error, _} ->
            {:noreply, CommitStatus.put(socket, "timezone", {:error, failure_message(:settings)})}
        end
    end
  end

  # ============================================================================
  # Saving
  # ============================================================================

  # One commit, one outcome on the fact that made it. Success replaces the
  # company so every projection (title, header badge, parent name) is the
  # server's; refusal keeps the stored value on screen and says what was
  # rejected and why.
  defp save_fact(socket, name, attrs, submitted) do
    case commit_company(socket, name, attrs, submitted) do
      {:ok, socket} -> CommitStatus.put(socket, name, :saved)
      {:error, socket} -> socket
    end
  end

  defp commit_company(socket, name, attrs, submitted) do
    scope = socket.assigns.current_scope.scope
    company = socket.assigns.company

    case Company.update_company(scope, company.id, attrs) do
      {:ok, updated} ->
        {:ok,
         socket
         |> assign(:company, updated)
         |> assign(:page_title, Company.Summary.display_name(updated))}

      {:error, %Ecto.Changeset{} = changeset} ->
        message = refusal_message(name, submitted, changeset)
        {:error, CommitStatus.put(socket, name, {:error, message})}

      {:error, reason} ->
        {:error, CommitStatus.put(socket, name, {:error, failure_message(reason)})}
    end
  end

  defp decode_metadata(""), do: {:ok, nil}

  defp decode_metadata(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> :invalid
    end
  end

  # The shared wording names the rejected value, the fact's label and the
  # changeset's reasons for the field the fact writes.
  defp refusal_message(name, submitted, %Ecto.Changeset{} = changeset) do
    CommitStatus.refusal_message(fact_label(name), fact_field(name), submitted, changeset.errors)
  end

  defp fact_field("activities"), do: :scope_activities
  defp fact_field("metadata"), do: :metadata
  defp fact_field(name), do: Map.get(@inline_fields, name) || Map.fetch!(@choice_fields, name)

  defp failure_message(:not_found),
    do: "This company no longer exists in this workspace. Return to the list to find it."

  defp failure_message(_reason), do: CommitStatus.failure_message()

  defp write_forbidden(socket) do
    CommitStatus.write_forbidden(
      socket,
      "You do not have permission to change company administration data."
    )
  end

  # Every write re-asks Authz: the `can_update?` assign decides what the page
  # shows, and a grant revoked while the page is open must still be refused.
  defp can_update?(socket) do
    Authz.can(socket.assigns.current_scope.actor, @update_capability).allowed
  end

  defp fact_label(name), do: Map.fetch!(@fact_labels, name)

  # What the operator chose, as a refusal names it: the option's label when it
  # came from this page's list, "None" for the blank option, and the raw
  # value for anything else.
  defp choice_label(_socket, _name, ""), do: "None"
  defp choice_label(_socket, "status", value), do: String.capitalize(value)

  defp choice_label(socket, "legal_entity_type_id", value),
    do: option_label(legal_entity_type_options(socket.assigns.legal_entity_types), value)

  defp choice_label(socket, "jurisdiction", value),
    do: option_label(country_options(socket.assigns.countries), value)

  defp choice_label(socket, "parent_id", value),
    do: option_label(parent_company_options(socket.assigns.parent_companies), value)

  defp option_label(options, value) do
    Enum.find_value(options, value, fn {label, option} ->
      if to_string(option) == value, do: label
    end)
  end

  defp normalize_param(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
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
  # Helpers: Options and names
  # ============================================================================

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
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin this company to sidebar"
              context={:inline}
              id="company-pin"
              data-nav-pin="record"
              data-nav-pin-record="true"
              data-nav-pin-label={"Administration / Companies / #{@company.name}"}
              data-nav-pin-url={~p"/companies/#{@company.id}"}
              aria-pressed="false"
              />
          </:title_actions>
          <:subtitle>
            <%!-- Belimbing: title=name, subtitle=legal_name. Repeating the
                 name when no distinct legal name exists says nothing, so the
                 code stands in (#622). --%>
            {if @company.legal_name && @company.legal_name != @company.name,
              do: @company.legal_name,
              else: @company.code}
          </:subtitle>
          <:actions>
            <%!-- Status is record metadata, not an action: it leads the row so
                 the demoted actions (History, then Back) cluster after it
                 (#685). This row holds no button — the pin icon action sits
                 in the title row above: Departments and Relationships are
                 reached from the sections that list them, as Belimbing's
                 admin/companies/show does, so the header never duplicates a
                 section's own "Manage" link. --%>
            <div class="flex items-center gap-3">
              <.status_badge status={@company.status} />
              <.discovered_panel
                key="record.history"
                id="company-record-history"
                current_scope={@current_scope}
                opts={%{auditable_types: company_auditable_types(), auditable_id: @company.id}}
              />
              <.back_link id="company-back" navigate={~p"/companies"} title="Back to companies" />
            </div>
          </:actions>
        </.header>

        <.alert :if={@is_primary} kind={:info} class="mt-4">
          This is the primary company representing its tenant.
        </.alert>

        <%!-- Section 1: Company Details. The facts are the shared `<.list>`
             and the heading row is the shared `<.section_heading>`, as on
             every section of this page; Business Activities and Metadata are
             facts of the same record, so they are rows of the same list, as
             Belimbing's company-details partial renders them. Each fact edits
             in place and reports on itself; the heading carries no button. --%>
        <.card
          id="company-details-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-details-heading"
        >
          <.section_heading id="company-details-heading" title="Company Details" />

          <.list>
            <:item title={fact_label("name")} id="detail-name">
              <.text_fact
                name="name"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
                class="font-semibold"
              />
            </:item>
            <:item title={fact_label("code")} id="detail-code">
              <.text_fact
                name="code"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
                class="font-mono"
              />
            </:item>
            <:item title={fact_label("legal_name")} id="detail-legal-name">
              <.text_fact
                name="legal_name"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
              />
            </:item>
            <:item title={fact_label("status")} id="detail-status">
              <.choice_fact
                id="company-status"
                name="status"
                value={@company.status}
                options={@status_options}
                editing?={@editing_field == "status"}
                can_update?={@can_update?}
                status={@field_status["status"]}
              >
                <.status_badge status={@company.status} />
              </.choice_fact>
            </:item>
            <:item title={fact_label("legal_entity_type_id")} id="detail-legal-entity-type">
              <.choice_fact
                id="company-legal-entity-type"
                name="legal_entity_type_id"
                value={@company.legal_entity_type_id}
                options={legal_entity_type_options(@legal_entity_types)}
                prompt="None"
                editing?={@editing_field == "legal_entity_type_id"}
                can_update?={@can_update?}
                status={@field_status["legal_entity_type_id"]}
              >
                <.read_value value={
                  legal_entity_type_name(@company.legal_entity_type_id, @legal_entity_types)
                } />
              </.choice_fact>
            </:item>
            <:item title={fact_label("registration_number")} id="detail-registration-number">
              <.text_fact
                name="registration_number"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
              />
            </:item>
            <:item title={fact_label("tax_id")} id="detail-tax-id">
              <.text_fact
                name="tax_id"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
              />
            </:item>
            <:item title={fact_label("jurisdiction")} id="detail-jurisdiction">
              <.choice_fact
                id="company-jurisdiction"
                name="jurisdiction"
                value={@company.jurisdiction}
                options={country_options(@countries)}
                prompt="None"
                editing?={@editing_field == "jurisdiction"}
                can_update?={@can_update?}
                status={@field_status["jurisdiction"]}
              >
                <.read_value value={country_name(@company.jurisdiction, @countries)} />
              </.choice_fact>
            </:item>
            <:item title={fact_label("email")} id="detail-email">
              <.text_fact
                name="email"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
              />
            </:item>
            <:item title={fact_label("website")} id="detail-website">
              <.text_fact
                :if={@can_update?}
                name="website"
                company={@company}
                can_update?={@can_update?}
                field_status={@field_status}
              />
              <a
                :if={not @can_update? and @company.website}
                href={@company.website}
                target="_blank"
                rel="noopener noreferrer"
                class="text-action hover:underline"
              >
                {@company.website}
              </a>
              <span :if={not @can_update? and !@company.website} class="text-ink-muted">—</span>
            </:item>
            <:item title={fact_label("parent_id")} id="detail-parent">
              <.choice_fact
                id="company-parent"
                name="parent_id"
                value={@company.parent_id}
                options={parent_company_options(@parent_companies)}
                prompt="None"
                editing?={@editing_field == "parent_id"}
                can_update?={@can_update?}
                status={@field_status["parent_id"]}
              >
                {parent_name(@company.parent_id, @parent_companies) || "None"}
              </.choice_fact>
            </:item>

            <:item title={fact_label("activities")} id="scope-activities-section">
              <p class="text-xs text-ink-subtle">
                Industry, services, and business focus areas of this company.
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <%= for {activity, idx} <- Enum.with_index(@company.scope_activities || []) do %>
                  <span class="inline-flex items-center gap-1 rounded-full border border-line bg-surface-sunken px-3 py-1 text-xs font-medium text-ink">
                    {activity}
                    <.icon_button
                      :if={@can_update?}
                      icon="close"
                      label={"Remove #{activity}"}
                      context={:inline}
                      kind={:danger}
                      id={"remove-activity-#{idx}"}
                      phx-click="remove_activity"
                      phx-value-index={idx}
                      data-confirm={
                        "Remove the business activity #{activity}? " <>
                          "The change is saved immediately."
                      }
                    />
                  </span>
                <% end %>
                <span
                  :if={
                    not @can_update? and
                      (is_nil(@company.scope_activities) or @company.scope_activities == [])
                  }
                  class="text-ink-muted"
                >
                  —
                </span>
                <%!-- Belimbing adds an activity through a "+ Add" chip that
                     opens an input committing on Enter or blur; the shared
                     in-place text control is that same flow, and the fact
                     reports adding and removing on it. --%>
                <.inline_edit
                  :if={@can_update?}
                  id="company-new-activity"
                  name="activity"
                  label="Add business activity"
                  value=""
                  placeholder="Add activity"
                  id_value={@company.id}
                  save_event="add_activity"
                  status={@field_status["activities"]}
                  class="min-w-56"
                />
              </div>
            </:item>

            <:item title={fact_label("metadata")} id="company-metadata">
              <div :if={not @editing_metadata?} class="flex items-start gap-2">
                <%= if @company.metadata do %>
                  <pre
                    id="company-metadata-display"
                    class="min-w-0 flex-1 overflow-x-auto rounded-xl bg-surface-sunken p-3 text-xs font-mono text-ink"
                  >{format_metadata(@company.metadata)}</pre>
                <% else %>
                  <span class="text-ink-muted">—</span>
                <% end %>
                <%!-- A JSON document is the one fact Enter cannot commit, so
                     it keeps an explicit Apply. Belimbing opens its textarea
                     from a pencil beside the label; here the demoted icon
                     action sits beside the value, where the edit lands. --%>
                <.icon_button
                  :if={@can_update?}
                  id="edit-metadata-btn"
                  icon="edit"
                  label="Edit metadata"
                  context={:inline}
                  phx-click="edit_metadata"
                />
              </div>

              <%!-- Window-scoped, as the choice editors are: Escape cancels
                   wherever focus is. --%>
              <div
                :if={@can_update? and @editing_metadata?}
                phx-window-keydown="cancel_edit_metadata"
                phx-key="Escape"
              >
                <form id="metadata-form" phx-submit="save_metadata" class="space-y-2">
                  <textarea
                    name="metadata"
                    id="company-metadata-json"
                    rows="5"
                    aria-label="Company metadata JSON"
                    phx-mounted={JS.focus()}
                    class="w-full rounded-md border border-line bg-surface p-3 text-xs font-mono text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30"
                    placeholder='{"employee_count": 120, "founded_year": 2014}'
                  >{@metadata_input}</textarea>
                  <div class="flex items-center gap-2">
                    <.button
                      id="company-metadata-apply"
                      type="submit"
                      variant="primary"
                      class="text-xs"
                      phx-disable-with="Applying…"
                    >
                      Apply
                    </.button>
                    <.button
                      id="company-metadata-cancel"
                      type="button"
                      phx-click="cancel_edit_metadata"
                      class="text-xs"
                    >
                      Cancel
                    </.button>
                  </div>
                </form>
              </div>

              <.commit_status id="company-metadata-status" status={@field_status["metadata"]} />
            </:item>
          </.list>
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

        <%!-- Section 3: Timezone. A company setting rather than a column,
             presented as one choice fact of its own section: Belimbing keeps
             its combobox always visible with a saved note beside it; here the
             read state is the trigger, as every choice fact on this page. --%>
        <.card
          id="company-timezone-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-timezone-heading"
        >
          <.section_heading id="company-timezone-heading" title="Timezone">
            <:description>
              Default timezone for this company. Used when displaying dates and times in Company mode.
            </:description>
          </.section_heading>

          <.list>
            <:item title={fact_label("timezone")} id="detail-timezone">
              <.choice_fact
                id="company-timezone"
                name="timezone"
                value={@company_timezone}
                options={timezone_options(@company_timezone)}
                prompt={"Not configured (#{@resolved_timezone})"}
                save_event="save_timezone"
                editing?={@editing_field == "timezone"}
                can_update?={@can_update?}
                status={@field_status["timezone"]}
              >
                <span :if={@company_timezone != ""}>{@company_timezone}</span>
                <span :if={@company_timezone == ""} class="text-ink-muted">
                  Not configured ({@resolved_timezone})
                </span>
              </.choice_fact>
            </:item>
          </.list>

          <div :if={@company_timezone == ""} class="mt-4">
            <.alert kind={:info}>
              No timezone is configured for this company. Dates and times will display in {@resolved_timezone} until a timezone is set.
            </.alert>
          </div>
        </.card>

        <%!-- Section 4: Subsidiaries (Child Companies) --%>
        <.card
          :if={@children != []}
          id="company-subsidiaries-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-subsidiaries-heading"
        >
          <.section_heading
            id="company-subsidiaries-heading"
            title="Subsidiaries"
            count={length(@children)}
          />

          <.table
            id="company-subsidiaries-table"
            rows={@children}
            row_id={fn child -> "child-company-#{child.id}" end}
            row_item={fn child -> child end}
            caption="Subsidiaries"
            framed={false}
          >
            <:col :let={child} label="Name">
              <.link
                navigate={~p"/companies/#{child.id}"}
                class="font-medium text-action hover:underline"
              >
                {child.name}
              </.link>
            </:col>
            <:col :let={child} label="Status">
              <.status_badge status={child.status} />
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
        <.card
          id="company-departments-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-departments-heading"
        >
          <.section_heading
            id="company-departments-heading"
            title="Departments"
            count={length(@departments)}
          >
            <:actions>
              <.action_link
                id="company-departments-manage"
                icon="manage"
                navigate={~p"/companies/#{@company.id}/departments"}
                title="Manage departments"
              >
                Manage
              </.action_link>
            </:actions>
          </.section_heading>

          <.table
            id="company-departments-table"
            rows={@departments}
            row_id={fn dept -> "department-#{dept.id}" end}
            row_item={fn dept -> dept end}
            caption="Departments"
            framed={false}
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
        <.card
          id="company-relationships-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-relationships-heading"
        >
          <.section_heading
            id="company-relationships-heading"
            title="Relationships"
            count={length(@relationships)}
          >
            <:actions>
              <.action_link
                id="company-relationships-manage"
                icon="manage"
                navigate={~p"/companies/#{@company.id}/relationships"}
                title="Manage relationships"
              >
                Manage
              </.action_link>
            </:actions>
          </.section_heading>

          <.table
            id="company-relationships-table"
            rows={@relationships}
            row_id={fn rel -> "rel-#{rel.id}" end}
            row_item={fn rel -> rel end}
            caption="Relationships"
            framed={false}
          >
            <:col :let={rel} label="Company">
              <.link
                navigate={~p"/companies/#{rel.other_company.id}"}
                class="font-medium text-action hover:underline"
              >
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
        <.card
          id="company-external-accesses-card"
          class="mt-6"
          inner_class="p-5 sm:p-6"
          role="region"
          aria-labelledby="company-external-accesses-heading"
        >
          <.section_heading
            id="company-external-accesses-heading"
            title="External Accesses"
            count={length(@external_accesses)}
          />

          <.table
            id="company-external-accesses-table"
            rows={@external_accesses}
            row_id={fn access -> "access-#{access.id}" end}
            row_item={fn access -> access end}
            caption="External Accesses"
            framed={false}
          >
            <:col :let={access} label="User">
              <%= if name = @external_access_names[access.user_id] do %>
                <.link
                  navigate={~p"/users/#{access.user_id}"}
                  class="font-medium text-action hover:underline"
                >
                  {name}
                </.link>
              <% else %>
                <span class="text-ink-subtle">—</span>
              <% end %>
            </:col>
            <:col :let={access} label="Permissions">
              <div
                :if={is_list(access.permissions) and access.permissions != []}
                class="flex flex-wrap gap-1"
              >
                <.badge :for={permission <- access.permissions}>{permission}</.badge>
              </div>
              <span
                :if={not (is_list(access.permissions) and access.permissions != [])}
                class="text-ink-subtle"
              >
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
          opts={
            %{company_id: @company.id, table_state: @employees_table_state, page_sizes: @page_sizes}
          }
        />
      </.page>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Fact Components
  # ============================================================================

  # A read-first text fact's value cell. An operator who may update edits it in
  # place; an emptied value is a real edit only on a nullable column. Anyone
  # else sees the stored value with no affordance. The row around it — label,
  # value cell and its id — is the shared `<.list>` item.
  attr(:name, :string, required: true)
  attr(:company, Company.Summary, required: true)
  attr(:can_update?, :boolean, required: true)
  attr(:field_status, :map, required: true)
  attr(:class, :any, default: nil)

  defp text_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:value, Map.fetch!(assigns.company, Map.fetch!(@inline_fields, assigns.name)))
      |> assign(:dom_id, "company-#{String.replace(assigns.name, "_", "-")}")
      |> assign(:allow_empty, assigns.name in @nullable_inline_facts)

    ~H"""
    <.inline_edit
      :if={@can_update?}
      id={@dom_id}
      name={@name}
      label={@label}
      value={@value || ""}
      id_value={@company.id}
      save_event="save_field"
      allow_empty={@allow_empty}
      status={@field_status[@name]}
      class={@class}
    />
    <span :if={not @can_update?} class={[@class, is_nil(@value) && "text-ink-muted"]}>
      {@value || "—"}
    </span>
    """
  end

  # A read-first choice fact's value cell, in the shape `/addresses/:id` and
  # `/users/:id` give theirs: the read state (the inner block) is the trigger
  # for an operator who may update, the select appears on click and commits
  # on change, and Escape or leaving it cancels. Anyone else sees the read
  # state alone. The outcome of the last commit renders beneath.
  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:value, :any, required: true)
  attr(:options, :list, required: true)
  attr(:prompt, :string, default: nil)
  attr(:save_event, :string, default: "save_choice")
  attr(:editing?, :boolean, required: true)
  attr(:can_update?, :boolean, required: true)
  attr(:status, :any, required: true)
  slot(:inner_block, required: true)

  defp choice_fact(assigns) do
    assigns =
      assigns
      |> assign(:label, fact_label(assigns.name))
      |> assign(:current, to_string(assigns.value || ""))

    ~H"""
    <button
      :if={@can_update? and not @editing?}
      type="button"
      id={"#{@id}-display"}
      phx-click="edit_field"
      phx-value-field={@name}
      aria-label={"Edit #{String.downcase(@label)}"}
      aria-describedby={@status && "#{@id}-status"}
      class="group -mx-1.5 flex max-w-full min-w-0 cursor-pointer items-center gap-1.5 rounded px-1.5 py-0.5 text-left transition-colors hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-brand-strong"
    >
      {render_slot(@inner_block)}
      <.icon
        name="edit"
        class="size-3.5 shrink-0 text-ink-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
      />
    </button>

    <%!-- Window-scoped: the select may not hold focus (JS.focus is
         best-effort), and Escape must cancel regardless. Only one choice
         editor mounts at a time, so the listener is unambiguous. --%>
    <div :if={@can_update? and @editing?} phx-window-keydown="cancel_edit_field" phx-key="Escape">
      <form id={"#{@id}-form"} phx-change={@save_event} class="inline-block">
        <select
          id={"#{@id}-select"}
          name={@name}
          aria-label={@label}
          phx-mounted={JS.focus()}
          phx-blur="cancel_edit_field"
          class="rounded-md border border-line bg-surface px-2.5 py-1 text-xs text-ink focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong"
        >
          <option :if={@prompt} value="" selected={@current == ""}>{@prompt}</option>
          <option
            :for={{label, option} <- @options}
            value={option}
            selected={to_string(option) == @current}
          >
            {label}
          </option>
        </select>
      </form>
    </div>

    <span :if={not @can_update?}>{render_slot(@inner_block)}</span>

    <.commit_status id={"#{@id}-status"} status={@status} />
    """
  end

  # A choice fact's read state for a nullable relation: the resolved name, or
  # the muted em dash.
  attr(:value, :string, default: nil)

  defp read_value(assigns) do
    ~H"""
    <span :if={@value}>{@value}</span>
    <span :if={is_nil(@value)} class="text-ink-muted">—</span>
    """
  end

  attr(:status, :string, required: true)

  defp status_badge(assigns) do
    ~H"""
    <.badge kind={status_badge_kind(@status)}>{String.capitalize(@status)}</.badge>
    """
  end

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("suspended"), do: :danger
  defp status_badge_kind("pending"), do: :warning
  defp status_badge_kind(_status), do: :neutral

  # The stored timezone stays choosable even when it is not one of the common
  # options this page offers.
  defp timezone_options(""), do: Enum.map(@common_timezones, &{&1, &1})

  defp timezone_options(current) do
    [current | @common_timezones] |> Enum.uniq() |> Enum.map(&{&1, &1})
  end
end
