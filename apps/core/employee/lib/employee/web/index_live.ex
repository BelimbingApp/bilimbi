defmodule Bilimbi.Core.Employee.Web.IndexLive do
  @moduledoc """
  Employees for the signed-in company, via `Bilimbi.Core.Employee.list_administration_page/3`.

  There is no tenant-wide employee list. Affiliation is company-scoped.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.AdministrationPage

  @delete_capability "admin.employee.delete"

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25

  # URL keys stay `sort`, `dir`, `type`, and `per_page`. ListState's own query
  # names are `sort_by` and `sort_dir`; this page translates at the boundary
  # so an existing link still opens the same list. Inbound sort aliases
  # (`name`, `type`, `employee_type`) become the column the header uses.
  @sort_aliases %{
    "name" => "full_name",
    "full_name" => "full_name",
    "type" => "employee_type_label",
    "employee_type" => "employee_type_label",
    "employee_type_label" => "employee_type_label",
    "status" => "status"
  }

  @list ListState.spec!(
          sortable: %{full_name: :asc, employee_type_label: :asc, status: :asc},
          default_sort: :full_name,
          page_sizes: @page_sizes,
          default_page_size: @default_page_size,
          page_size_param: "per_page",
          invalid_page_size: :default,
          filters: [type_filter: {:one_of, ["all", "human", "agent"], "all"}],
          omit_blank: [:search]
        )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Employees")
     |> assign(:active_nav, "admin.employee")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:index_state, parse_list(%{}))
     |> assign(:employees_page, empty_page())
     |> assign(:department_map, %{})
     |> assign(:pending_delete, nil)
     |> assign(:filters_form, ListState.filters_form(parse_list(%{})))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, parse_list(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) when is_map(filters) do
    state =
      socket.assigns.index_state
      |> ListState.apply_filters(filters)
      |> trim_search()

    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    state = socket.assigns.index_state

    case ListState.next_sort(state, sort_by) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_patch(socket, to: employees_path(next))}
    end
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    state = ListState.put_page(socket.assigns.index_state, page)
    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  @impl true
  # Deleting confirms through the shared dialog: the request holds the listed
  # employee whose consequence the dialog states, and `delete` acts on that held
  # employee rather than on a client-supplied id, so what was confirmed is what
  # runs.
  def handle_event("request_delete", %{"id" => id}, socket) do
    case authorize_delete(socket) do
      {:denied, socket} ->
        {:noreply, assign(socket, :pending_delete, nil)}

      {:ok, socket} ->
        employee = find_listed(socket, id)

        if employee do
          {:noreply, socket |> clear_flash() |> assign(:pending_delete, employee)}
        else
          {:noreply,
           socket
           |> put_flash(:error, "That employee no longer exists.")
           |> load_page(socket.assigns.index_state)}
        end
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("delete", _params, socket) do
    case authorize_delete(socket) do
      {:denied, socket} ->
        {:noreply, assign(socket, :pending_delete, nil)}

      {:ok, socket} ->
        if is_nil(socket.assigns.pending_delete) do
          {:noreply, socket}
        else
          employee = socket.assigns.pending_delete
          socket = assign(socket, :pending_delete, nil)
          scope = resolve_scope(socket)
          company_id = resolve_company_id(socket)

          case Employee.delete_employee(scope, company_id, employee.id) do
            :ok ->
              {:noreply,
               socket
               |> put_flash(:success, "#{employee.full_name} was deleted.")
               |> load_page(socket.assigns.index_state)}

            {:error, :employee_not_found} ->
              {:noreply,
               socket
               |> put_flash(:error, "That employee no longer exists.")
               |> load_page(socket.assigns.index_state)}

            {:error, :invariant_violation} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "#{employee.full_name} was not deleted: the platform orchestrator cannot be deleted."
               )}

            {:error, :forbidden} ->
              {:noreply, put_flash(socket, :error, LiveAuthorization.denied_message())}

            {:error, _reason} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "#{employee.full_name} was not deleted. Reload the page and try again."
               )}
          end
        end
    end
  end

  defp find_listed(socket, id) do
    case Params.positive_integer(id) do
      employee_id when is_integer(employee_id) ->
        Enum.find(socket.assigns.employees_page.entries, &(&1.id == employee_id))

      _ ->
        nil
    end
  end

  defp load_page(socket, state) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    options = [
      page: state.page,
      page_size: state.page_size,
      search: Params.blank_to_nil(state.search),
      type_filter: type_atom(state.filters.type_filter),
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Employee.list_administration_page(scope, company_id, options) do
      {:ok, %AdministrationPage{} = page} ->
        corrected = ListState.clamp_to_last_page(state, page, empty: :reset)

        if corrected.page != state.page do
          push_patch(socket, to: employees_path(corrected))
        else
          socket
          |> assign(:index_state, state)
          |> assign(:employees_page, page)
          |> assign(:department_map, department_map(scope, company_id))
          |> assign(:company_id, company_id)
          |> assign(:filters_form, ListState.filters_form(state))
          |> stream(:employees, page.entries, reset: true)
        end

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load employees.")
        |> assign(:index_state, state)
        |> assign(:employees_page, empty_page())
        |> stream(:employees, [], reset: true)
    end
  end

  defp empty_page do
    %AdministrationPage{
      entries: [],
      page: 1,
      page_size: @default_page_size,
      total_entries: 0,
      total_pages: 0,
      has_prev?: false,
      has_next?: false
    }
  end

  # Department names come through Company's public API, same as the show
  # page — the departments table belongs to Core Company, not this module.
  defp department_map(scope, company_id) do
    case Company.list_departments(scope, company_id) do
      {:ok, departments} ->
        Map.new(departments, fn dept ->
          {dept.id, if(dept.type, do: dept.type.name, else: "Department #{dept.id}")}
        end)

      _ ->
        %{}
    end
  end

  # `allowed?/2` on the row only decides whether the control is shown.
  defp authorize_delete(socket) do
    LiveAuthorization.authorize_event(socket, @delete_capability)
  end

  defp resolve_scope(socket) do
    socket.assigns.current_scope.scope
  end

  defp resolve_company_id(socket) do
    socket.assigns.current_scope.user["company_id"]
  end

  defp parse_list(params) do
    params
    |> translate_inbound()
    |> ListState.parse(@list)
    |> trim_search()
  end

  defp translate_inbound(params) when is_map(params) do
    %{
      "search" => first_present(params, ["search", "q"]),
      "page" => params["page"],
      "per_page" => first_present(params, ["per_page", "perPage"]),
      "sort_by" => sort_alias(params["sort"]),
      "sort_dir" => downcase_binary(params["dir"]),
      "type_filter" => downcase_binary(first_present(params, ["type", "type_filter"]))
    }
  end

  defp translate_inbound(_params), do: %{}

  defp first_present(params, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(params, key) do
        value when is_binary(value) -> value
        _ -> nil
      end
    end)
  end

  defp sort_alias(value) when is_binary(value) do
    key = value |> String.trim() |> String.downcase()
    Map.get(@sort_aliases, key, key)
  end

  defp sort_alias(_value), do: nil

  defp downcase_binary(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp downcase_binary(_value), do: nil

  defp trim_search(%ListState{search: search} = state) do
    %{state | search: Params.trimmed(search)}
  end

  defp type_atom("human"), do: :human
  defp type_atom("agent"), do: :agent
  defp type_atom(_value), do: :all

  defp employees_path(%ListState{} = state) do
    params =
      []
      |> maybe_put(:search, present_search(state.search))
      |> maybe_put(:type, present_type(state.filters.type_filter))
      |> maybe_put(:sort, present_sort(state))
      |> maybe_put(:dir, present_dir(state))
      |> maybe_put(:page, present_page(state))
      |> maybe_put(:per_page, present_page_size(state))

    case params do
      [] -> ~p"/employees"
      _ -> ~p"/employees?#{params}"
    end
  end

  defp present_search(search) when search in [nil, ""], do: nil
  defp present_search(search), do: search

  defp present_type("all"), do: nil
  defp present_type(type), do: type

  defp present_sort(%ListState{sort_by: sort_by, spec: %{default_sort: sort_by}}), do: nil
  defp present_sort(%ListState{sort_by: sort_by}), do: Atom.to_string(sort_by)

  defp present_dir(%ListState{sort_by: sort_by, sort_dir: sort_dir, spec: %{sortable: sortable}}) do
    if sort_dir == Map.fetch!(sortable, sort_by), do: nil, else: Atom.to_string(sort_dir)
  end

  defp present_page(%ListState{page: 1}), do: nil
  defp present_page(%ListState{page: page}), do: page

  defp present_page_size(%ListState{page_size: size, spec: %{default_page_size: size}}), do: nil
  defp present_page_size(%ListState{page_size: size}), do: size

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

  defp status_badge_kind("active"), do: :success
  defp status_badge_kind("probation"), do: :warning
  defp status_badge_kind("terminated"), do: :danger
  defp status_badge_kind(_status), do: :neutral

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employees-index">
        <.header>
          Employees
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Employees to sidebar"
              context={:inline}
              id="employees-pin"
              data-nav-pin="nav-admin-employee"
              aria-pressed="false"
            />
          </:title_actions>
          <:subtitle>People employed by {@current_scope.user["company_name"]}</:subtitle>

          <:actions>
            <div class="flex items-center gap-3">
              <.button
                :if={allowed?(@current_scope, "admin.employee.create")}
                id="employee-new"
                navigate={~p"/employees/new"}
                variant="primary"
              >
                New Employee
              </.button>

              <.action_link
                :if={allowed?(@current_scope, "admin.employee-type.list")}
                id="employee-types"
                icon="manage"
                navigate={~p"/employee-types"}
                title="Manage employee types"
              >
                Employee Types
              </.action_link>
            </div>
          </:actions>
        </.header>

        <.filter_toolbar id="employees-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="employees-search"
            label="Search employees"
            placeholder="Search by name, employee number, email, designation, or job description..."
          />
          <:control
            type={:select}
            field={@filters_form[:type_filter]}
            id="employees-type-filter"
            label="Type filter"
            options={[
              {"All types", "all"},
              {"Human only", "human"},
              {"Agent only", "agent"}
            ]}
          />
        </.filter_toolbar>

        <.card id="employees-card" inner_class="p-0">
          <h2 id="employees-table-title" class="sr-only">Employees</h2>

          <.table
            id="employees"
            rows={@streams.employees}
            row_id={fn {id, _employee} -> id end}
            row_item={fn {_id, employee} -> employee end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={employee} label="Name" sort="full_name" sort_id="employees-sort-name">
              <.record_link
                workspace={@workspace}
                kind="core/employee"
                record_id={employee.id}
                navigate={~p"/employees/#{employee.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {employee.full_name}
              </.record_link>

              <span :if={employee.designation} class="block text-xs text-ink-subtle">
                {employee.designation}
              </span>
            </:col>

            <:col :let={employee} label="No.">
              <code class="text-xs font-medium tabular-nums">{employee.employee_number}</code>
            </:col>

            <:col :let={employee} label="Department">
              <span class={[is_nil(employee.department_id) && "text-ink-faint"]}>
                {Map.get(@department_map, employee.department_id, "—")}
              </span>
            </:col>

            <:col
              :let={employee}
              label="Type"
              sort="employee_type_label"
              sort_id="employees-sort-type"
            >
              <.badge kind={:neutral} dot={false}>
                {employee.employee_type_label || employee.employee_type}
              </.badge>
            </:col>

            <:col :let={employee} label="Status" sort="status" sort_id="employees-sort-status">
              <.badge kind={status_badge_kind(employee.status)}>
                {employee.status}
              </.badge>
            </:col>

            <:action :let={employee}>
              <div class="flex items-center justify-end gap-3">
                <.icon_button
                  :if={allowed?(@current_scope, "admin.employee.delete")}
                  icon="delete"
                  label={"Delete #{employee.full_name}"}
                  kind={:danger}
                  id={"employee-#{employee.id}-delete"}
                  phx-click="request_delete"
                  phx-value-id={employee.id}
                />
              </div>
            </:action>

            <:empty :if={@employees_page.entries == []}>
              No employees found.
            </:empty>
          </.table>

          <.pagination
            id="employees-pagination"
            page={@employees_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>

        <.confirm_dialog
          :if={@pending_delete}
          id="delete-employee-confirm"
          consequence={"#{@pending_delete.full_name} will be deleted."}
          detail="The employment record is removed and the person no longer appears in the directory. This cannot be undone."
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />
      </.page>
    </Layouts.app>
    """
  end
end
