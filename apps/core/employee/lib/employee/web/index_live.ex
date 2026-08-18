defmodule Bilimbi.Core.Employee.Web.IndexLive do
  @moduledoc """
  Employees for the signed-in company, via `Bilimbi.Core.Employee.list_administration_page/3`.

  There is no tenant-wide employee list. Affiliation is company-scoped.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.AdministrationPage

  @page_sizes [10, 15, 25, 50, 100]
  @default_page_size 25
  @sorts %{
    "name" => :full_name,
    "full_name" => :full_name,
    "type" => :employee_type_label,
    "employee_type" => :employee_type_label,
    "employee_type_label" => :employee_type_label,
    "status" => :status
  }
  @type_filters %{
    "all" => :all,
    "human" => :human,
    "agent" => :agent
  }
  @maximum_search_bytes 255

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Employees")
     |> assign(:active_nav, "admin.employee")
     |> stream_configure(:employees, dom_id: &"employee-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", params, socket) do
    filters = Map.get(params, "filters", %{})

    state =
      socket.assigns.index_state
      |> Map.put(:search, normalize_search(Map.get(filters, "search", "")))
      |> Map.put(:type_filter, normalize_type_filter(Map.get(filters, "type_filter", "all")))
      |> Map.put(
        :page_size,
        normalize_page_size(Map.get(filters, "perPage", socket.assigns.index_state.page_size))
      )
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  def handle_event("sort", %{"sort" => requested_sort}, socket) do
    {:noreply,
     push_patch(socket, to: employees_path(next_sort(socket.assigns.index_state, requested_sort)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.employees_page)
      )

    {:noreply, push_patch(socket, to: employees_path(state))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.employee.delete") do
      scope = socket.assigns.current_scope.scope
      company_id = socket.assigns.current_scope.user["company_id"]

      with {employee_id, ""} <- Integer.parse(to_string(id)),
           :ok <- Employee.delete_employee(scope, company_id, employee_id) do
        {:noreply,
         socket
         |> put_flash(:info, "Employee deleted successfully.")
         |> push_patch(to: employees_path(socket.assigns.index_state))}
      else
        {:error, :invariant_violation} ->
          {:noreply, put_flash(socket, :error, "The platform orchestrator cannot be deleted.")}

        {:error, :employee_not_found} ->
          {:noreply, put_flash(socket, :error, "That employee does not exist in this company.")}

        _ ->
          {:noreply, put_flash(socket, :error, "That employee could not be deleted.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to that action.")}
    end
  end

  defp load_page(socket, state) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

    options = [
      page: state.page,
      page_size: state.page_size,
      search: state.search,
      type_filter: state.type_filter,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Employee.list_administration_page(scope, company_id, options) do
      {:ok, %AdministrationPage{} = page} ->
        socket
        |> assign(:index_state, state)
        |> assign(:employees_page, page)
        |> assign(:company_id, company_id)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> stream(:employees, page.entries, reset: true)

      {:error, :company_not_found} ->
        socket
        |> put_flash(:error, "That company is not in this workspace.")
        |> push_navigate(to: ~p"/dashboard")

      {:error, _reason} ->
        socket
        |> assign(:index_state, state)
        |> assign(:employees_page, %AdministrationPage{
          entries: [],
          page: state.page,
          page_size: state.page_size,
          total_entries: 0,
          total_pages: 0,
          has_prev?: false,
          has_next?: false
        })
        |> assign(:company_id, company_id)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> stream(:employees, [], reset: true)
    end
  end

  defp state_from_params(params) do
    %{
      search: normalize_search(Map.get(params, "search", "")),
      type_filter: normalize_type_filter(Map.get(params, "type_filter", "all")),
      sort_by: normalize_sort(Map.get(params, "sort", "full_name")),
      sort_dir: normalize_direction(Map.get(params, "direction", "asc")),
      page: normalize_page(Map.get(params, "page", "1")),
      page_size: normalize_page_size(Map.get(params, "per_page", @default_page_size))
    }
  end

  defp next_sort(state, requested_sort) do
    normalized_requested = normalize_sort(requested_sort)

    direction =
      if state.sort_by == normalized_requested do
        flip_direction(state.sort_dir)
      else
        :asc
      end

    %{state | sort_by: normalized_requested, sort_dir: direction, page: 1}
  end

  defp filters_form_params(state) do
    %{
      "search" => state.search,
      "type_filter" => Atom.to_string(state.type_filter),
      "perPage" => Integer.to_string(state.page_size)
    }
  end

  defp employees_path(state) do
    query = %{
      "search" => (state.search != "" && state.search) || nil,
      "type_filter" => (state.type_filter != :all && Atom.to_string(state.type_filter)) || nil,
      "sort" => sort_param(state.sort_by),
      "direction" => (state.sort_dir != :asc && Atom.to_string(state.sort_dir)) || nil,
      "page" => (state.page > 1 && Integer.to_string(state.page)) || nil,
      "per_page" =>
        (state.page_size != @default_page_size && Integer.to_string(state.page_size)) || nil
    }

    ~p"/employees?#{query}"
  end

  defp sort_param(:full_name), do: nil
  defp sort_param(:employee_type_label), do: "type"
  defp sort_param(:status), do: "status"
  defp sort_param(_), do: nil

  defp normalize_search(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {graphemes, bytes} ->
      next_bytes = bytes + byte_size(grapheme)

      if next_bytes <= @maximum_search_bytes do
        {:cont, {[grapheme | graphemes], next_bytes}}
      else
        {:halt, {graphemes, bytes}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp normalize_search(_value), do: ""

  defp normalize_type_filter(value) when is_binary(value) do
    Map.get(@type_filters, value, :all)
  end

  defp normalize_type_filter(value) when is_atom(value) and value in [:all, :human, :agent],
    do: value

  defp normalize_type_filter(_value), do: :all

  defp normalize_sort(value) when is_map_key(@sorts, value), do: Map.fetch!(@sorts, value)

  defp normalize_sort(value)
       when is_atom(value) and value in [:full_name, :employee_type_label, :status],
       do: value

  defp normalize_sort(_value), do: :full_name

  defp normalize_direction("desc"), do: :desc
  defp normalize_direction(:desc), do: :desc
  defp normalize_direction(_value), do: :asc

  defp flip_direction(:asc), do: :desc
  defp flip_direction(_direction), do: :asc

  defp normalize_page(value) do
    case positive_integer(value) do
      nil -> 1
      page -> page
    end
  end

  defp normalize_page_size(value) do
    requested = positive_integer(value) || @default_page_size
    Enum.find(@page_sizes, List.last(@page_sizes), &(&1 >= requested))
  end

  defp bounded_page(value, page) do
    requested = normalize_page(value)
    requested |> min(max(page.total_pages, 1)) |> max(1)
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp page_size_options, do: Enum.map(@page_sizes, &{"#{&1} rows", &1})

  defp page_summary(%{total_entries: 0}), do: "No employees found"

  defp page_summary(%{entries: [], total_entries: total_entries}) do
    "No employees on this page · #{total_entries} total"
  end

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first}–#{last} of #{total_entries}"
  end

  defp page_position(%{total_pages: 0}), do: "Page 0 of 0"

  defp page_position(%{page: page, total_pages: total_pages}) do
    "Page #{page} of #{total_pages}"
  end

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
            <button
              type="button"
              id="employees-pin"
              data-nav-pin="nav-admin-employee"
              title="Pin Employees to sidebar"
              aria-label="Pin Employees to sidebar"
              aria-pressed="false"
              class="grid size-5 place-items-center rounded-sm text-ink-faint transition hover:bg-surface-sunken hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
            >
              <.icon name="bilimbi-pin" class="size-3.5" />
            </button>
          </:title_actions>
          <:subtitle>People employed by {@current_scope.user["company_name"]}</:subtitle>

          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.employee-type.list")}
              navigate={~p"/employee-types"}
              id="employee-types"
            >
              Employee Types
            </.button>

            <.button
              :if={allowed?(@current_scope, "admin.employee.create")}
              id="employee-new"
              navigate={~p"/employees/new"}
              variant="primary"
            >
              New Employee
            </.button>
          </:actions>
        </.header>

        <.card id="employees-card" inner_class="p-0">
          <h2 id="employees-table-title" class="sr-only">Employees</h2>
          <.form
            for={@filters_form}
            id="employees-filters"
            phx-change="filters"
            class="p-2 mb-2"
          >
            <div class="grid gap-2 md:grid-cols-[minmax(0,1fr)_minmax(12rem,16rem)_10rem]">
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
                />
                <.input
                  field={@filters_form[:search]}
                  id="employees-search"
                  type="search"
                  phx-debounce="300"
                  maxlength="255"
                  label="Search employees"
                  label_class="sr-only"
                  wrapper_class="mb-0"
                  placeholder="Search by name, employee number, email, designation..."
                  class="block w-full rounded-lg border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-action focus:outline-none focus:ring-2 focus:ring-action/20"
                />
              </div>
              <.input
                field={@filters_form[:type_filter]}
                id="employees-type-filter"
                type="select"
                label="Type filter"
                label_class="sr-only"
                wrapper_class="mb-0"
                options={[
                  {"All types", "all"},
                  {"Human only", "human"},
                  {"Agent only", "agent"}
                ]}
              />
              <.input
                field={@filters_form[:perPage]}
                id="employees-page-size"
                type="select"
                label="Rows per page"
                label_class="sr-only"
                wrapper_class="mb-0"
                options={page_size_options()}
              />
            </div>
          </.form>

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
              <.link
                navigate={~p"/employees/#{employee.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {employee.full_name}
              </.link>

              <span :if={employee.designation} class="block text-xs text-ink-subtle">
                {employee.designation}
              </span>
            </:col>

            <:col :let={employee} label="No.">
              <code class="text-xs font-medium tabular-nums">{employee.employee_number}</code>
            </:col>

            <:col
              :let={employee}
              label="Type"
              sort="employee_type_label"
              sort_id="employees-sort-type"
            >
              <.badge kind={:neutral}>
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
                <.link
                  :if={allowed?(@current_scope, "admin.employee.update")}
                  id={"employee-#{employee.id}-edit"}
                  navigate={~p"/employees/#{employee.id}/edit"}
                  class="text-xs font-semibold text-action hover:underline"
                >
                  Edit
                </.link>
                <button
                  :if={allowed?(@current_scope, "admin.employee.delete")}
                  id={"employee-#{employee.id}-delete"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={employee.id}
                  data-confirm={"Are you sure you want to delete #{employee.full_name}?"}
                  title="Delete employee"
                  class="rounded-md border border-danger-line bg-danger-surface px-2.5 py-1.5 text-xs font-semibold text-danger-ink transition hover:bg-danger"
                >
                  Delete
                </button>
              </div>
            </:action>

            <:empty :if={@employees_page.entries == []}>
              No employees found.
            </:empty>
          </.table>

          <nav
            :if={@employees_page.total_pages > 0}
            id="employees-pagination"
            aria-label="Pagination"
            class="flex items-center justify-between gap-3 border-t border-line px-4 py-3"
          >
            <p id="employees-pagination-summary" class="text-xs text-ink-subtle">
              {page_summary(@employees_page)}
            </p>
            <div class="flex items-center gap-2">
              <.button
                id="employees-pagination-previous"
                phx-click="page"
                phx-value-page={@employees_page.page - 1}
                disabled={@employees_page.page <= 1}
              >
                Previous
              </.button>
              <span id="employees-pagination-position" class="text-xs tabular-nums text-ink-muted">
                {page_position(@employees_page)}
              </span>
              <.button
                id="employees-pagination-next"
                phx-click="page"
                phx-value-page={@employees_page.page + 1}
                disabled={
                  @employees_page.page >= @employees_page.total_pages or
                    @employees_page.total_pages == 0
                }
              >
                Next
              </.button>
            </div>
          </nav>
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
