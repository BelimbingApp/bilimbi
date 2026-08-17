defmodule Bilimbi.Core.Address.Web.IndexLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Address

  @sorts ~w(label country_iso verification_status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :addresses, dom_id: &"address-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(:search, Map.get(filters, "search", ""))
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

  def handle_event("delete", %{"id" => id}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.address.delete") do
      delete_address(socket, id)
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to delete addresses.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div id="addresses-index" class="mx-auto max-w-7xl">
        <.header>
          Addresses
          <:actions>
            <.button
              :if={allowed?(@current_scope, "admin.address.create")}
              id="address-create"
              navigate={~p"/addresses/create"}
              variant="primary"
            >
              <.icon name="hero-plus" /> Create Address
            </.button>
          </:actions>
        </.header>

        <section class="rounded-xl border border-line bg-surface" aria-label="Address list">
          <.form
            for={@filters_form}
            id="addresses-filters"
            phx-change="filters"
            class="px-4 pt-4"
          >
            <.input
              field={@filters_form[:search]}
              id="addresses-search"
              type="search"
              phx-debounce="300"
              label="Search addresses"
              placeholder="Search by label, address, locality, postcode, or country..."
            />
          </.form>

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
              <span class="whitespace-nowrap font-medium text-ink">{address.label || "Unlabeled"}</span>
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
              <button
                :if={allowed?(@current_scope, "admin.address.delete")}
                id={"address-delete-#{address.id}"}
                type="button"
                phx-click="delete"
                phx-value-id={address.id}
                data-confirm={"Delete #{address.label || "this address"}?"}
                class="text-xs font-medium text-danger hover:underline"
              >
                Delete
              </button>
            </:action>
            <:empty :if={@addresses_page.entries == []}>
              No addresses found.
            </:empty>
          </.table>

          <nav
            id="addresses-pagination"
            aria-label="Address pagination"
            class="flex items-center justify-between gap-3 border-t border-line-subtle px-4 py-3"
          >
            <p id="addresses-pagination-summary" class="text-xs text-ink-subtle">
              {page_summary(@addresses_page)}
            </p>
            <div class="flex items-center gap-2">
              <button
                id="addresses-page-previous"
                type="button"
                phx-click="page"
                phx-value-page={@addresses_page.page - 1}
                disabled={@addresses_page.page <= 1}
                class="rounded-md border border-line bg-surface px-2.5 py-1.5 text-xs font-medium text-ink transition hover:bg-surface-sunken disabled:cursor-not-allowed disabled:opacity-50"
              >
                Previous
              </button>
              <span class="text-xs tabular-nums text-ink-muted">
                {page_position(@addresses_page)}
              </span>
              <button
                id="addresses-page-next"
                type="button"
                phx-click="page"
                phx-value-page={@addresses_page.page + 1}
                disabled={
                  @addresses_page.total_pages == 0 or
                    @addresses_page.page >= @addresses_page.total_pages
                }
                class="rounded-md border border-line bg-surface px-2.5 py-1.5 text-xs font-medium text-ink transition hover:bg-surface-sunken disabled:cursor-not-allowed disabled:opacity-50"
              >
                Next
              </button>
            </div>
          </nav>
        </section>
      </div>
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
    |> assign(:filters_form, to_form(%{"search" => state.search}, as: :filters))
    |> assign(:index_state, state)
    |> stream(:addresses, page.entries, reset: true)
  end

  defp address_page(socket, state) do
    Address.list_addresses(socket.assigns.current_scope.scope,
      search: state.search,
      page: state.page,
      sort_by: String.to_existing_atom(state.sort_by),
      sort_dir: String.to_existing_atom(state.sort_dir)
    )
  end

  defp delete_address(socket, id) do
    with {address_id, ""} <- Integer.parse(id),
         :ok <- Address.delete_address(socket.assigns.current_scope.scope, address_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Address deleted successfully.")
       |> load_page(socket.assigns.index_state)}
    else
      {:error, :address_in_use} ->
        {:noreply,
         put_flash(socket, :error, "This address is linked. Unlink it before deleting it.")}

      _error ->
        {:noreply, put_flash(socket, :error, "That address could not be deleted.")}
    end
  end

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      page: parse_page(Map.get(params, "page")),
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
    ~p"/addresses?#{%{search: state.search, page: state.page, sortBy: state.sort_by, sortDir: state.sort_dir}}"
  end

  defp normalize_sort(value) when value in @sorts, do: value
  defp normalize_sort(_value), do: "label"

  defp normalize_direction(value) when value in ["asc", "desc"], do: value
  defp normalize_direction(_value), do: "asc"

  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

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

  defp page_summary(%{total_entries: 0}), do: "No results"

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first}–#{last} of #{total_entries}"
  end

  defp page_position(%{total_pages: 0}), do: "Page 0 of 0"

  defp page_position(%{page: page, total_pages: total_pages}),
    do: "Page #{page} of #{total_pages}"
end
