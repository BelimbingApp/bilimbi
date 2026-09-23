defmodule Bilimbi.Core.Address.Web.IndexLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Address

  @page_sizes [25, 50, 100]
  @default_page_size 25
  @sorts ~w(label country_iso verification_status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:pending_delete, nil)
     |> stream_configure(:addresses, dom_id: &"address-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", socket.assigns.index_state.search))
      |> Map.put(:per_page, Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: addresses_path(state))}
  end

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: addresses_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.addresses_page)
      )

    {:noreply, push_patch(socket, to: addresses_path(state))}
  end

  # Deleting confirms through the shared dialog: the request holds the listed
  # address whose consequence the dialog states, and `delete` acts on that held
  # address rather than on a client-supplied id, so what was confirmed is what
  # runs.
  def handle_event("request_delete", %{"id" => id}, socket) do
    cond do
      not allowed?(socket.assigns.current_scope, "admin.address.delete") ->
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
      not allowed?(socket.assigns.current_scope, "admin.address.delete") ->
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

        <.form
          for={@filters_form}
          id="addresses-filters"
          phx-change="filters"
          class="mb-2"
        >
          <div class="relative">
            <.icon
              name="search"
              class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-faint"
            />
            <.input
              field={@filters_form[:search]}
              id="addresses-search"
              type="search"
              phx-debounce="300"
              label="Search addresses"
              label_class="sr-only"
              wrapper_class="mb-0"
              placeholder="Search by label, address, locality, postcode, or country..."
              class="block w-full rounded-md border border-line bg-surface py-1.5 pl-8 pr-3 text-sm text-ink shadow-xs transition placeholder:text-ink-faint focus:border-brand-strong focus:outline-none focus:ring-2 focus:ring-brand-strong/30"
            />
          </div>
        </.form>

        <.card id="addresses-card" inner_class="p-0">


          <.table
            id="addresses-table"
            rows={@streams.addresses}
            row_id={fn {dom_id, _address} -> dom_id end}
            row_item={fn {_dom_id, address} -> address end}
            sort_by={@index_state.sort_by}
            sort_dir={@index_state.sort_dir}
            framed={false}
          >
            <:col :let={address} label="Label" sort="label" sort_id="addresses-sort-label">
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
            <:col :let={address} label="Address">
              <div class="min-w-56 text-ink-muted">
                <span>{address.line1 || "—"}</span>
                <span :if={address.line2} class="block text-xs text-ink-subtle">
                  {address.line2}
                </span>
              </div>
            </:col>
            <:col :let={address} label="Locality">
              <div class="whitespace-nowrap text-ink-muted">
                <span>{address.locality || "—"}</span>
                <span :if={address.postcode} class="block text-xs tabular-nums text-ink-subtle">
                  {address.postcode}
                </span>
              </div>
            </:col>
            <:col :let={address} label="Country" sort="country_iso" sort_id="addresses-sort-country">
              <span class="whitespace-nowrap font-mono text-xs text-ink-muted">
                {address.country_iso || "—"}
              </span>
            </:col>
            <:col
              :let={address}
              label="Status"
              sort="verification_status"
              sort_id="addresses-sort-status"
            >
              <.badge kind={status_kind(address.verification_status)}>
                {address.verification_status}
              </.badge>
            </:col>
            <:action :let={address}>
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
          </.table>

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
    state = bound_state_page(state, page)
    page = if state.page == page.page, do: page, else: address_page(socket, state)

    socket
    |> assign(:page_title, "Addresses")
    |> assign(:active_nav, "admin.address")
    |> assign(:addresses_page, page)
    |> assign(:page_sizes, @page_sizes)
    |> assign(
      :filters_form,
      to_form(%{"search" => state.search, "perPage" => state.per_page}, as: :filters)
    )
    |> assign(:index_state, state)
    |> stream(:addresses, page.entries, reset: true)
  end

  defp address_page(socket, state) do
    Address.list_addresses(socket.assigns.current_scope.scope,
      search: state.search,
      page: state.page,
      page_size: state.per_page,
      sort_by: String.to_existing_atom(state.sort_by),
      sort_dir: String.to_existing_atom(state.sort_dir)
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

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      page: parse_page(Map.get(params, "page")),
      per_page: normalize_page_size(Map.get(params, "perPage")),
      sort_by: normalize_sort(Map.get(params, "sortBy")),
      sort_dir: normalize_direction(Map.get(params, "sortDir"))
    }
  end

  defp next_sort(state, sort_by) do
    sort_by = normalize_sort(sort_by)

    %{
      state
      | page: 1,
        sort_by: sort_by,
        sort_dir: if(state.sort_by == sort_by, do: flip_direction(state.sort_dir), else: "asc")
    }
  end

  defp addresses_path(state) do
    ~p"/addresses?#{%{search: state.search, page: state.page, perPage: state.per_page, sortBy: state.sort_by, sortDir: state.sort_dir}}"
  end

  defp normalize_sort(value) when value in @sorts, do: value
  defp normalize_sort(_value), do: "label"

  defp normalize_direction(value) when value in ["asc", "desc"], do: value
  defp normalize_direction(_value), do: "asc"

  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

  defp normalize_page_size(value) do
    case parse_page(value) do
      size when size in @page_sizes -> size
      _size -> @default_page_size
    end
  end

  defp parse_page(value) when is_integer(value) and value > 0, do: value

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp bounded_page(value, page) do
    value
    |> parse_page()
    |> min(max(page.total_pages, 1))
    |> max(1)
  end

  defp bound_state_page(state, %{total_pages: total_pages})
       when total_pages > 0 and state.page > total_pages,
       do: %{state | page: total_pages}

  defp bound_state_page(state, _page), do: state

  defp status_kind("verified"), do: :success
  defp status_kind("suggested"), do: :warning
  defp status_kind(_status), do: :neutral
end
