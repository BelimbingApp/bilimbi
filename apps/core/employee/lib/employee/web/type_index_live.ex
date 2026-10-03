defmodule Bilimbi.Core.Employee.Web.TypeIndexLive do
  @moduledoc """
  Employee types available to the signed-in company.

  System types are company-less; custom types belong to the company.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params
  alias Bilimbi.Core.Employee

  @delete_capability "admin.employee-type.delete"

  @active_nav "admin.employee-type"
  @default_page_size 25
  @page_sizes [25, 50, 100, 300]

  # URL keys stay `sort`, `dir`, and `per_page`. A new click on Kind or
  # Employees opens descending; Code and Label open ascending. Inbound
  # aliases `kind` and `employees` become those columns.
  @sort_aliases %{
    "code" => "code",
    "label" => "label",
    "kind" => "is_system",
    "is_system" => "is_system",
    "employees" => "employees_count",
    "employees_count" => "employees_count"
  }

  @list ListState.spec!(
          sortable: %{code: :asc, label: :asc, is_system: :desc, employees_count: :desc},
          default_sort: :is_system,
          page_sizes: @page_sizes,
          default_page_size: @default_page_size,
          page_size_param: "per_page",
          invalid_page_size: :default,
          omit_blank: [:search]
        )

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
     |> assign(:deleting_type_id, nil)
     |> assign(:pending_delete, nil)
     |> stream(:employee_types, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    load_page(socket, parse_list(params))
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) when is_map(filters) do
    state =
      socket.assigns.index_state
      |> ListState.apply_filters(filters)
      |> trim_search()

    {:noreply, push_patch(socket, to: employee_types_path(state))}
  end

  def handle_event("filters", params, socket) when is_map(params) do
    handle_event("filters", %{"filters" => params}, socket)
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_key}, socket) do
    state = socket.assigns.index_state

    case ListState.next_sort(state, sort_key) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_patch(socket, to: employee_types_path(next))}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    state = ListState.put_page(socket.assigns.index_state, page)
    {:noreply, push_patch(socket, to: employee_types_path(state))}
  end

  @impl true
  # Deleting confirms through the shared dialog: the request holds the listed
  # type whose consequence the dialog states, and `delete` starts the async
  # delete of that held type rather than of a client-supplied id, so what was
  # confirmed is what runs. A request while another delete is still in flight
  # is refused before any dialog opens, so nobody confirms a delete that would
  # not be served.
  def handle_event("request_delete", %{"id" => id_str}, socket) do
    case authorize_delete(socket) do
      {:denied, socket} ->
        {:noreply, assign(socket, :pending_delete, nil)}

      {:ok, socket} ->
        type = find_listed(socket, id_str)

        if type do
          request_delete(socket, type)
        else
          {:noreply,
           put_flash(socket, :error, "That employee type does not exist in this company.")}
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
          type = socket.assigns.pending_delete

          socket
          |> assign(:pending_delete, nil)
          |> start_delete(type.id)
        end
    end
  end

  # `allowed?/2` on the row only decides whether the control is shown.
  defp authorize_delete(socket) do
    LiveAuthorization.authorize_event(socket, @delete_capability)
  end

  defp find_listed(socket, id_str) do
    case Params.positive_integer(id_str) do
      type_id when is_integer(type_id) ->
        Enum.find(socket.assigns.employee_types_page.entries, &(&1.id == type_id))

      _ ->
        nil
    end
  end

  @impl true
  def handle_async(:delete_employee_type, {:ok, :ok}, socket) do
    socket =
      socket
      |> assign(:deleting_type_id, nil)
      |> put_flash(:success, "Employee type deleted.")

    load_page(socket, socket.assigns.index_state)
  end

  def handle_async(:delete_employee_type, {:ok, {:error, :in_use}}, socket) do
    {:noreply, delete_failed(socket, "Cannot delete: employees are using this type.")}
  end

  def handle_async(:delete_employee_type, {:ok, {:error, :is_system}}, socket) do
    {:noreply, delete_failed(socket, "System employee types cannot be deleted.")}
  end

  def handle_async(:delete_employee_type, {:ok, {:error, :type_not_found}}, socket) do
    {:noreply, delete_failed(socket, "That employee type does not exist in this company.")}
  end

  def handle_async(:delete_employee_type, {:ok, {:error, :forbidden}}, socket) do
    {:noreply, delete_failed(socket, LiveAuthorization.denied_message())}
  end

  def handle_async(:delete_employee_type, {:ok, {:error, :company_not_found}}, socket) do
    {:noreply,
     socket
     |> delete_failed("That company is not in this workspace.")
     |> push_navigate(to: ~p"/dashboard")}
  end

  def handle_async(:delete_employee_type, _result, socket) do
    {:noreply, delete_failed(socket, "Could not delete employee type.")}
  end

  # `start_async/3` is keyed by name, so one delete runs at a time. A repeat of
  # the row already deleting is the request that is already running and needs
  # nothing; any other request is refused out loud rather than dropped in
  # silence, and no dialog opens for a delete that would not be served.
  defp request_delete(socket, type) do
    case socket.assigns.deleting_type_id do
      nil ->
        {:noreply, socket |> clear_flash() |> assign(:pending_delete, type)}

      id when id == type.id ->
        {:noreply, socket}

      _another ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Another employee type is still being deleted. Try again once it finishes."
         )}
    end
  end

  # The delete runs outside the event so the row can paint its in-flight state
  # first; an icon-only control cannot use `phx-disable-with`, which would
  # replace its glyph with text.
  defp start_delete(socket, type_id) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    {:noreply,
     socket
     |> assign(:deleting_type_id, type_id)
     |> restream_type(type_id)
     |> start_async(:delete_employee_type, fn ->
       Employee.delete_employee_type(scope, company_id, type_id)
     end)}
  end

  defp delete_failed(socket, message) do
    type_id = socket.assigns.deleting_type_id

    socket
    |> assign(:deleting_type_id, nil)
    |> restream_type(type_id)
    |> put_flash(:error, message)
  end

  # Rows are streamed, so a busy state reaches the DOM only when its own item
  # is re-inserted.
  defp restream_type(socket, type_id) do
    case Enum.find(socket.assigns.employee_types_page.entries, &(&1.id == type_id)) do
      nil -> socket
      type -> stream_insert(socket, :employee_types, type)
    end
  end

  defp load_page(socket, %ListState{} = state) do
    scope = resolve_scope(socket)
    company_id = resolve_company_id(socket)

    options = [
      page: state.page,
      page_size: state.page_size,
      search: state.search,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    case Employee.list_type_administration_page(scope, company_id, options) do
      {:ok, page} ->
        corrected = ListState.clamp_to_last_page(state, page)

        if corrected.page != state.page do
          {:noreply, push_patch(socket, to: employee_types_path(corrected))}
        else
          {:noreply,
           socket
           |> assign(:index_state, state)
           |> assign(:employee_types_page, page)
           |> assign(:employee_types_count, page.total_entries)
           |> assign(:filters_form, ListState.filters_form(state))
           |> stream(:employee_types, page.entries, reset: true)}
        end

      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That company is not in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, :invalid_options} ->
        {:noreply, push_patch(socket, to: employee_types_path(parse_list(%{})))}
    end
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
      "search" => params["search"],
      "page" => params["page"],
      "per_page" => params["per_page"],
      "sort_by" => sort_alias(params["sort"]),
      "sort_dir" => downcase_binary(params["dir"])
    }
  end

  defp translate_inbound(_params), do: %{}

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

  defp employee_types_path(%ListState{} = state) do
    params =
      []
      |> maybe_put(:search, present_search(state.search))
      |> maybe_put(:dir, present_dir(state))
      |> maybe_put(:sort, present_sort(state))
      |> maybe_put(:page, present_page(state))
      |> maybe_put(:per_page, present_page_size(state))

    case params do
      [] -> ~p"/employee-types"
      _ -> ~p"/employee-types?#{params}"
    end
  end

  defp present_search(search) when search in [nil, ""], do: nil
  defp present_search(search), do: search

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="employee-types-index">
        <.header>
          Employee Types
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Employee Types to sidebar"
              context={:inline}
              id="employee-types-pin"
              data-nav-pin="nav-admin-employee-type"
              aria-pressed="false"
            />
          </:title_actions>
          <:subtitle>Manage employee type reference data</:subtitle>

          <:actions>
            <.back_link id="employee-types-back" navigate={~p"/employees"} title="Back to employees" />
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

        <.filter_toolbar id="employee-types-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="employee-types-search"
            label="Search employee types"
            placeholder="Search by code or label..."
          />
        </.filter_toolbar>

        <.card id="employee-types-card" inner_class="p-0">
          <h2 id="employee-types-table-title" class="sr-only">Employee Types</h2>

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
              <.link
                id={"employee-type-#{type.id}-link"}
                navigate={~p"/employee-types/#{type.id}"}
                class="font-medium text-ink-strong hover:underline"
              >
                {type.label}
              </.link>
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
                <.icon_button
                  :if={allowed?(@current_scope, "admin.employee-type.update")}
                  icon="edit"
                  label={"Edit #{type.label}"}
                  id={"employee-type-edit-#{type.id}"}
                  navigate={~p"/employee-types/#{type.id}"}
                />
                <.icon_button
                  :if={allowed?(@current_scope, "admin.employee-type.delete")}
                  icon="delete"
                  label={"Delete #{type.label}"}
                  kind={:danger}
                  id={"employee-type-delete-#{type.id}"}
                  phx-click="request_delete"
                  phx-value-id={type.id}
                  busy={@deleting_type_id == type.id}
                />
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

        <.confirm_dialog
          :if={@pending_delete}
          id="delete-employee-type-confirm"
          consequence={"Employee type “#{@pending_delete.label}” will be deleted."}
          detail="It can no longer be chosen for an employee. This cannot be undone."
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
