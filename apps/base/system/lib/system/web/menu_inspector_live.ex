defmodule Bilimbi.Base.System.Web.MenuInspectorLive do
  @moduledoc """
  Diagnostic listing of every contributed menu item.

  Ports Belimbing's `app/Base/System/Livewire/MenuInspector/Index.php`.
  Belimbing also shows a condition column and an extension kind filter.
  `Bilimbi.Base.Menu.Item` does not carry conditions and no Extension is
  installed yet; this page lists id, label, parent, container vs leaf,
  capability, route, source module, whether the route is served, and whether
  the current actor is allowed the capability. Search and source filter
  cover those fields.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Nav

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @builtins [
    %{id: "id", label: "ID"},
    %{id: "label", label: "Label"},
    %{id: "parent", label: "Parent"},
    %{id: "kind", label: "Kind"},
    %{id: "capability", label: "Capability"},
    %{id: "route", label: "Route"},
    %{id: "served", label: "Served"},
    %{id: "source", label: "Source"},
    %{id: "allowed", label: "Allowed"}
  ]

  # No sort. Empty search and source stay off the URL. `source=all` is the
  # same as no source. `perPage` is accepted inbound because the page-size
  # select posts it; the URL writes `page_size`.
  @list ListState.spec!(
          page_sizes: @page_sizes,
          default_page_size: @default_page_size,
          page_size_param: "page_size",
          page_size_aliases: ["perPage"],
          omit_blank: [:search, :source],
          filters: [source: {:string, "", %{"all" => ""}}]
        )

  @impl true
  def mount(_params, _session, socket) do
    state = ListState.parse(%{}, @list)

    {:ok,
     socket
     |> assign(:page_title, "Menu Inspector")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:state, state)
     |> assign(:sources, [])
     |> assign(:filters_form, ListState.filters_form(state))
     |> assign(:items_page, empty_page())
     |> assign(:total_entries, 0)
     |> assign(:columns, ListColumns.mount("menu-inspector", @builtins))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = ListState.parse(params, @list)
    {rows, sources} = visible_rows(socket, state)
    total_entries = length(rows)
    pages = total_pages(total_entries, state.page_size)
    corrected = ListState.clamp_to_last_page(state, %{total_pages: pages}, empty: :reset)

    if corrected.page != state.page do
      {:noreply, push_state(socket, corrected)}
    else
      {:noreply, assign_listing(socket, state, rows, sources, total_entries, pages)}
    end
  end

  @impl true
  # The toolbar and `<.pagination>`'s rows-per-page select both post under
  # `filters`. A key the posting form did not carry keeps its current value.
  def handle_event("filter", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, ListState.put_page(socket.assigns.state, page))}
  end

  @impl true
  def handle_event("grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/system/menu-inspector?#{ListState.to_params(state)}")
  end

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  defp visible_rows(socket, state) do
    all_rows = inspect_rows(socket.assigns.current_scope)

    rows =
      all_rows
      |> filter_by_source(state.filters.source)
      |> search_rows(state.search)

    {rows, available_sources(all_rows)}
  end

  defp assign_listing(socket, state, rows, sources, total_entries, pages) do
    entries = Enum.slice(rows, (state.page - 1) * state.page_size, state.page_size)

    socket
    |> assign(:sources, sources)
    |> assign(:state, state)
    |> assign(:filters_form, ListState.filters_form(state))
    |> assign(:total_entries, total_entries)
    |> assign(:items_page, %{
      page: state.page,
      page_size: state.page_size,
      total_entries: total_entries,
      total_pages: pages
    })
    |> assign(:columns, ListColumns.load(socket.assigns.columns, entries, & &1.id))
  end

  defp empty_page do
    %{page: 1, page_size: @default_page_size, total_entries: 0, total_pages: 0}
  end

  defp inspect_rows(current_scope) do
    Enum.map(Menu.items(), fn item ->
      %{
        id: item.id,
        label: item.label,
        parent: item.parent,
        kind: if(Menu.Item.container?(item), do: "container", else: "leaf"),
        capability: Bilimbi.Base.Menu.Capability.label(item.capability),
        route: item.route,
        source: item.source,
        served?: is_nil(item.route) or Nav.served?(item.route),
        allowed?: is_nil(item.capability) or allowed?(current_scope, item.capability)
      }
    end)
  end

  defp available_sources(rows) do
    rows
    |> Enum.map(& &1.source)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filter_by_source(rows, nil), do: rows
  defp filter_by_source(rows, ""), do: rows
  defp filter_by_source(rows, "all"), do: rows

  defp filter_by_source(rows, source) do
    Enum.filter(rows, &(&1.source == source))
  end

  defp search_rows(rows, ""), do: rows

  defp search_rows(rows, search) do
    needle = String.downcase(search)

    Enum.filter(rows, fn row ->
      Enum.any?(
        [row.id, row.label, row.parent, row.capability, row.route, row.source],
        fn
          nil -> false
          value -> String.contains?(String.downcase(value), needle)
        end
      )
    end)
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total, page_size), do: div(total + page_size - 1, page_size)
end
