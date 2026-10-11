defmodule Bilimbi.Core.Address.Web.IndexLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Address

  @page_sizes [25, 50, 100]
  @builtins [
    %{id: "label", label: "Label", type: :string, sort: "label", sort_id: "addresses-sort-label"},
    %{id: "address", label: "Address", type: :string},
    %{id: "locality", label: "Locality", type: :string},
    %{
      id: "country_iso",
      label: "Country",
      type: :string,
      sort: "country_iso",
      sort_id: "addresses-sort-country"
    },
    %{
      id: "verification_status",
      label: "Status",
      type: :string,
      sort: "verification_status",
      sort_id: "addresses-sort-status"
    }
  ]

  @write_guard_opt_out ~w(grid)
  @list ListState.spec!(
          sortable: %{label: :asc, country_iso: :asc, verification_status: :asc},
          default_sort: :label,
          page_sizes: @page_sizes,
          default_page_size: 25,
          page_size_param: "perPage",
          invalid_page_size: :default
        )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:pending_delete, nil)
     |> assign(:columns, ListColumns.mount("addresses-table", @builtins))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, parse_index(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state = ListState.apply_filters(socket.assigns.index_state, filters)
    {:noreply, push_patch(socket, to: addresses_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    state = ListState.next_sort(socket.assigns.index_state, sort_by)
    {:noreply, push_patch(socket, to: addresses_path(state))}
  end

  def handle_event("grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      {:sort, column} -> handle_event("sort", %{"sort" => column}, socket)
      :noop -> {:noreply, socket}
    end
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      socket.assigns.index_state
      |> ListState.put_page(page)
      |> ListState.clamp_to_last_page(socket.assigns.addresses_page, empty: :reset)

    {:noreply, push_patch(socket, to: addresses_path(state))}
  end

  # Deleting confirms through the shared dialog: the request holds the listed
  # address whose consequence the dialog states, and `delete` acts on that held
  # address rather than on a client-supplied id, so what was confirmed is what
  # runs.
  def handle_event("request_delete", %{"id" => id}, socket) do
    cond do
      not Authz.can(socket.assigns.current_scope.scope, "admin.address.delete").allowed ->
        delete_forbidden(socket)

      address = find_listed(socket, id) ->
        {:noreply, socket |> clear_flash() |> assign(:pending_delete, address)}

      true ->
        {:noreply,
         socket
         |> put_flash(:error, "That address no longer exists.")
         |> load_page(socket.assigns.index_state)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("delete", _params, socket) do
    cond do
      not Authz.can(socket.assigns.current_scope.scope, "admin.address.delete").allowed ->
        delete_forbidden(socket)

      is_nil(socket.assigns.pending_delete) ->
        {:noreply, socket}

      true ->
        address = socket.assigns.pending_delete

        socket
        |> assign(:pending_delete, nil)
        |> delete_address(address)
    end
  end

  defp delete_forbidden(socket) do
    {:noreply, put_flash(socket, :error, "You do not have permission to delete addresses.")}
  end

  defp find_listed(socket, id) do
    case Integer.parse(id) do
      {address_id, ""} -> Enum.find(socket.assigns.addresses_page.entries, &(&1.id == address_id))
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="addresses-index">
        <.header>
          Addresses
          <:title_actions>
            <.icon_button
              icon="bilimbi-pin"
              label="Pin Addresses to sidebar"
              context={:inline}
              id="addresses-pin"
              data-nav-pin="nav-admin-address"
              aria-pressed="false"
            />
          </:title_actions>
          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.address.create")}
              id="address-create"
              navigate={~p"/addresses/create"}
              variant="primary"
            >
              <.icon name="create" /> Create Address
            </.button>
          </:actions>
        </.header>

        <.filter_toolbar id="addresses-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="addresses-search"
            label="Search addresses"
            placeholder="Search by label, address, locality, postcode, or country..."
          />
        </.filter_toolbar>

        <.card id="addresses-card" inner_class="p-0">
          <.flex_table
            id="addresses-table"
            framed={false}
            columns={@columns.column_views}
            rows={@columns.rows}
            mode={@columns.mode}
            zoom={@columns.zoom}
            suggestions={@columns.suggestions}
            add_query={@columns.add_query}
            row_id={&"address-#{&1}"}
            caption="Addresses"
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
          >
            <:col :let={%{record: address}} id="label">
              <.link
                :if={allowed?(@current_scope, "admin.address.view")}
                navigate={~p"/addresses/#{address.id}"}
                class="whitespace-nowrap font-medium text-action hover:underline"
              >
                {address.label || "Unlabeled"}
              </.link>
              <span
                :if={not allowed?(@current_scope, "admin.address.view")}
                class="whitespace-nowrap font-medium text-ink"
              >
                {address.label || "Unlabeled"}
              </span>
            </:col>
            <:col :let={%{record: address}} id="address">
              <div class="min-w-56 text-ink-muted">
                <span>{address.line1 || "—"}</span>
                <span
                  :if={not is_nil(address.line2) and @columns.mode == :normal}
                  class="block text-xs text-ink-subtle"
                >
                  {address.line2}
                </span>
              </div>
            </:col>
            <:col :let={%{record: address}} id="locality">
              <div class="whitespace-nowrap text-ink-muted">
                <span>{address.locality || "—"}</span>
                <span
                  :if={not is_nil(address.postcode) and @columns.mode == :normal}
                  class="block text-xs tabular-nums text-ink-subtle"
                >
                  {address.postcode}
                </span>
              </div>
            </:col>
            <:col :let={%{record: address}} id="country_iso">
              <span class="whitespace-nowrap font-mono text-xs text-ink-muted">
                {address.country_iso || "—"}
              </span>
            </:col>
            <:col :let={%{record: address}} id="verification_status">
              <.badge kind={status_kind(address.verification_status)}>
                {address.verification_status}
              </.badge>
            </:col>
            <:action :let={%{record: address}}>
              <.icon_button
                :if={allowed?(@current_scope, "admin.address.delete")}
                icon="delete"
                label={"Delete #{address.label || "address"}"}
                kind={:danger}
                id={"address-delete-#{address.id}"}
                phx-click="request_delete"
                phx-value-id={address.id}
              />
            </:action>
            <:empty :if={@addresses_page.entries == []}>
              No addresses found.
            </:empty>
          </.flex_table>

          <.pagination
            id="addresses-pagination"
            page={@addresses_page}
            page_sizes={@page_sizes}
            filters_form={@filters_form}
          />
        </.card>

        <.confirm_dialog
          :if={@pending_delete}
          id="delete-address-confirm"
          consequence={"#{address_name(@pending_delete)} will be deleted."}
          detail="It can no longer be attached to a company or employee. This cannot be undone."
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />
      </.page>
    </Layouts.app>
    """
  end

  defp load_page(socket, state) do
    page = address_page(socket, state)
    state = ListState.clamp_to_last_page(state, page)
    page = if state.page == page.page, do: page, else: address_page(socket, state)

    socket
    |> assign(:page_title, "Addresses")
    |> assign(:active_nav, "admin.address")
    |> assign(:addresses_page, page)
    |> assign(:page_sizes, @page_sizes)
    |> assign(:filters_form, ListState.filters_form(state))
    |> assign(:index_state, state)
    |> assign(:columns, ListColumns.load(socket.assigns.columns, page.entries, & &1.id))
  end

  defp address_page(socket, state) do
    Address.list_addresses(socket.assigns.current_scope.scope,
      search: state.search,
      page: state.page,
      page_size: state.page_size,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    )
  end

  defp delete_address(socket, address) do
    case Address.delete_address(socket.assigns.current_scope.scope, address.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:success, "Address deleted.")
         |> load_page(socket.assigns.index_state)}

      {:error, :address_in_use} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{address_name(address)} was not deleted: it is still attached to a company or " <>
             "employee. Unlink it there first."
         )}

      {:error, :address_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That address no longer exists.")
         |> load_page(socket.assigns.index_state)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{address_name(address)} was not deleted. Reload the page and try again."
         )}
    end
  end

  defp address_name(%{label: label}) when is_binary(label) and label != "", do: "“#{label}”"
  defp address_name(_address), do: "This address"

  defp parse_index(params) do
    ListState.parse(camel_params(params), @list)
  end

  defp camel_params(params) do
    params
    |> Map.put("sort_by", params["sortBy"])
    |> Map.put("sort_dir", params["sortDir"])
  end

  defp addresses_path(state) do
    query =
      state
      |> ListState.to_params()
      |> Map.drop(["sort_by", "sort_dir"])
      |> Map.put("sortBy", Atom.to_string(state.sort_by))
      |> Map.put("sortDir", Atom.to_string(state.sort_dir))

    ~p"/addresses?#{query}"
  end

  defp status_kind("verified"), do: :success
  defp status_kind("suggested"), do: :warning
  defp status_kind(_status), do: :neutral
end
