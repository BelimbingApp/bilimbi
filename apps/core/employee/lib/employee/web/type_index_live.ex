defmodule Bilimbi.Core.Employee.Web.TypeIndexLive do
  @moduledoc """
  Employee types available to the signed-in company.

  System types are company-less; custom types belong to the company.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Employee

  @active_nav "admin.employee-type"
  @default_page 1
  @default_page_size 25
  @page_sizes [25, 50, 100, 300]
  @sorts %{
    "code" => :code,
    "label" => :label,
    "kind" => :is_system,
    "is_system" => :is_system,
    "employees" => :employees_count,
    "employees_count" => :employees_count
  }

  defmodule State do
    @moduledoc false

    @enforce_keys [:page, :per_page, :search, :sort_by, :sort_dir]
    defstruct [:page, :per_page, :search, :sort_by, :sort_dir]

    @type t :: %__MODULE__{
            page: pos_integer(),
            per_page: pos_integer(),
            search: String.t() | nil,
            sort_by: :code | :label | :is_system | :employees_count,
            sort_dir: :asc | :desc
          }
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Set up initial state
      :ok
    end

    {:ok,
     socket
     |> assign(:page_title, "Employee Types")
     |> assign(:active_nav, @active_nav)
     |> assign(:page_sizes, @page_sizes)
     |> stream(:employee_types, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = parse_params(params)
    load_page(socket, state)
  end

  @impl true
  def handle_event("filters", %{"filters" => params}, socket) do
    handle_event("filters", params, socket)
  end

  def handle_event("filters", %{"search" => search, "perPage" => per_page}, socket) do
    parsed_per_page = positive_integer(per_page) || socket.assigns.index_state.per_page

    normalized_per_page =
      if parsed_per_page in @page_sizes, do: parsed_per_page, else: @default_page_size

    trimmed_search = String.trim(search)
    search_value = if trimmed_search == "", do: nil, else: trimmed_search

    new_state = %{
      socket.assigns.index_state
      | search: search_value,
        per_page: normalized_per_page,
        page: 1
    }

    {:noreply, push_patch(socket, to: employee_types_path(new_state))}
  end

  def handle_event("filters", %{"perPage" => per_page}, socket) do
    handle_event(
      "filters",
      %{"search" => socket.assigns.index_state.search || "", "perPage" => per_page},
      socket
    )
  end

  def handle_event("filters", %{"search" => search}, socket) do
    handle_event(
      "filters",
      %{"search" => search, "perPage" => to_string(socket.assigns.index_state.per_page)},
      socket
    )
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_key}, socket) do
    new_state = next_sort(socket.assigns.index_state, sort_key)
    {:noreply, push_patch(socket, to: employee_types_path(new_state))}
  end

  @impl true
  def handle_event("delete", %{"id" => id_str}, socket) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    if allowed?(socket.assigns.current_scope, "admin.employee-type.delete") do
      with {type_id, ""} <- Integer.parse(id_str),
           :ok <- Employee.delete_employee_type(scope, company_id, type_id) do
        socket = put_flash(socket, :info, "Employee type deleted.")
        load_page(socket, socket.assigns.index_state)
      else
        {:error, :in_use} ->
          {:noreply, put_flash(socket, :error, "Cannot delete: employees are using this type.")}

        {:error, :is_system} ->
          {:noreply, put_flash(socket, :error, "System employee types cannot be deleted.")}

        {:error, :type_not_found} ->
          {:noreply,
           put_flash(socket, :error, "That employee type does not exist in this company.")}

        {:error, :company_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "That company is not in this workspace.")
           |> push_navigate(to: ~p"/dashboard")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not delete employee type.")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "You do not have permission to delete employee types.")}
    end
  end

  defp load_page(socket, %State{} = state) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    options = [
      page: state.page,
      page_size: state.per_page,
      search: state.search || "",
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Employee.list_type_administration_page(scope, company_id, options) do
      {:ok, %{total_pages: total_pages}} when state.page > total_pages and total_pages > 0 ->
        target_page = max(1, total_pages)
        {:noreply, push_patch(socket, to: employee_types_path(%{state | page: target_page}))}

      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:index_state, state)
         |> assign(:employee_types_page, page)
         |> assign(:employee_types_count, page.total_entries)
         |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
         |> stream(:employee_types, page.entries, reset: true)}

      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, :invalid_options} ->
        fallback_state = %State{
          page: @default_page,
          per_page: @default_page_size,
          search: nil,
          sort_by: :is_system,
          sort_dir: :desc
        }

        {:noreply, push_patch(socket, to: employee_types_path(fallback_state))}
    end
  end

  defp resolve_scope(socket) do
    socket.assigns.current_scope.scope
  end

  defp resolve_company_id(socket) do
    socket.assigns.current_scope.user["company_id"]
  end

  defp parse_params(params) do
    page = positive_integer(params["page"]) || @default_page
    per_page = positive_integer(params["per_page"]) || @default_page_size
    per_page = if per_page in @page_sizes, do: per_page, else: @default_page_size

    search =
      case params["search"] do
        nil -> nil
        "" -> nil
        val -> String.trim(val)
      end

    sort_by = Map.get(@sorts, params["sort"], :is_system)

    default_dir =
      case sort_by do
        :code -> :asc
        :label -> :asc
        :is_system -> :desc
        :employees_count -> :desc
      end

    sort_dir =
      case params["dir"] do
        "asc" -> :asc
        "desc" -> :desc
        _ -> default_dir
      end

    %State{
      page: page,
      per_page: per_page,
      search: search,
      sort_by: sort_by,
      sort_dir: sort_dir
    }
  end

  defp positive_integer(nil), do: nil
  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp next_sort(state, sort_key) do
    field = Map.get(@sorts, sort_key, :is_system)

    if state.sort_by == field do
      %{state | sort_dir: toggle_sort_dir(state.sort_dir), page: 1}
    else
      default_dir =
        case field do
          :code -> :asc
          :label -> :asc
          :is_system -> :desc
          :employees_count -> :desc
        end

      %{state | sort_by: field, sort_dir: default_dir, page: 1}
    end
  end

  defp toggle_sort_dir(:asc), do: :desc
  defp toggle_sort_dir(:desc), do: :asc

  defp filters_form_params(state) do
    %{
      "search" => state.search || "",
      "perPage" => to_string(state.per_page)
    }
  end

  defp employee_types_path(state) do
    search_val = if state.search not in [nil, ""], do: state.search
    sort_val = if state.sort_by != :is_system, do: to_string(state.sort_by)

    default_dir =
      case state.sort_by do
        :code -> :asc
        :label -> :asc
        :is_system -> :desc
        :employees_count -> :desc
      end

    dir_val = if state.sort_dir != default_dir, do: to_string(state.sort_dir)
    page_val = if state.page != @default_page, do: state.page
    per_page_val = if state.per_page != @default_page_size, do: state.per_page

    params =
      []
      |> maybe_put(:search, search_val)
      |> maybe_put(:dir, dir_val)
      |> maybe_put(:sort, sort_val)
      |> maybe_put(:page, page_val)
      |> maybe_put(:per_page, per_page_val)

    case params do
      [] -> ~p"/employee-types"
      _ -> ~p"/employee-types?#{params}"
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employee-types-index">
        <p class="mb-2 text-xs">
          <.link navigate={~p"/employees"} class="font-medium text-ink-muted hover:text-ink">
            ← Employees
          </.link>
        </p>

        <.header>
          Employee Types
          <:title_actions>
            <button
              type="button"
              id="employee-types-pin"
              data-nav-pin="nav-admin-employee-type"
              title="Pin Employee Types to sidebar"
              aria-label="Pin Employee Types to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>Manage employee type reference data</:subtitle>

          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.employee-type.create")}
              id="employee-type-new"
              navigate={~p"/employee-types/new"}
              variant="primary"
            >
              New Type
            </.button>
          </:actions>
        </.header>

        <.card id="employee-types-card" inner_class="p-0">
          <h2 id="employee-types-table-title" class="sr-only">Employee Types</h2>
          <.form
            for={@filters_form}
            id="employee-types-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
              />
              <.input
                field={@filters_form[:search]}
                id="employee-types-search"
                type="search"
                phx-debounce="300"
                maxlength="255"
                label="Search employee types"
                label_class="sr-only"
                wrapper_class="mb-0"
                placeholder="Search by code or label..."
                class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
              />
            </div>
          </.form>

          <.table
            id="employee-types"
            rows={@streams.employee_types}
            row_id={fn {id, _type} -> id end}
            row_item={fn {_id, type} -> type end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={type} label="Code" sort="code" sort_id="employee-types-sort-code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>

            <:col :let={type} label="Label" sort="label" sort_id="employee-types-sort-label">
              <span class="text-sm font-medium text-ink">{type.label}</span>
            </:col>

            <:col :let={type} label="Kind" sort="is_system" sort_id="employee-types-sort-kind">
              <.badge kind={if type.is_system, do: :neutral, else: :success}>
                {if type.is_system, do: "system", else: "custom"}
              </.badge>
            </:col>

            <:col
              :let={type}
              label="Employees"
              sort="employees_count"
              sort_id="employee-types-sort-employees"
            >
              <span class="text-xs tabular-nums text-ink-subtle">{type.employees_count}</span>
            </:col>

            <:action :let={type}>
              <div :if={not type.is_system} class="flex items-center justify-end gap-3">
                <.link
                  :if={allowed?(@current_scope, "admin.employee-type.update")}
                  id={"employee-type-edit-#{type.id}"}
                  navigate={~p"/employee-types/#{type.id}/edit"}
                  class="text-xs font-semibold text-action hover:underline"
                >
                  Edit
                </.link>
                <button
                  :if={allowed?(@current_scope, "admin.employee-type.delete")}
                  id={"employee-type-delete-#{type.id}"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={type.id}
                  phx-disable-with="Deleting…"
                  data-confirm={"Are you sure you want to delete #{type.label}?"}
                  title="Delete employee type"
                  class="rounded-md border border-danger-line bg-danger-surface px-2.5 py-1.5 text-xs font-semibold text-danger-ink transition hover:bg-danger disabled:cursor-not-allowed disabled:opacity-50"
                >
                  Delete
                </button>
              </div>
              <%!-- The Kind column's System badge already says what this row
                   is; the actions cell is w-0, so prose here wraps word-per-
                   line and wrecks row density (#619). A lock with a tooltip
                   keeps the why reachable without repeating it per row. --%>
              <span
                :if={type.is_system}
                class="inline-flex items-center justify-end whitespace-nowrap text-ink-faint"
                title="System types cannot be edited"
              >
                <.icon name="hero-lock-closed" class="size-3.5" />
                <span class="sr-only">System types cannot be edited</span>
              </span>
            </:action>

            <:empty :if={@employee_types_page.entries == []}>
              No employee types found.
            </:empty>
          </.table>

          <.pagination
            id="employee-types-pagination"
            page={@employee_types_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
