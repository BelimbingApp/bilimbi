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
  alias Bilimbi.Base.UI.Nav

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25

  @impl true
  def mount(_params, _session, socket) do
    state = default_state()

    {:ok,
     socket
     |> assign(:page_title, "Menu Inspector")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:state, state)
     |> assign(:sources, [])
     |> assign(:filters_form, filters_form(state))
     |> assign(:items_page, empty_page())
     |> assign(:total_entries, 0)
     |> stream(:items, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = state_from_params(params)
    {rows, sources} = visible_rows(socket, state)
    total_entries = length(rows)
    pages = total_pages(total_entries, state.page_size)

    cond do
      pages > 0 and state.page > pages ->
        {:noreply, push_state(socket, %{state | page: pages})}

      pages == 0 and state.page > 1 ->
        {:noreply, push_state(socket, %{state | page: 1})}

      true ->
        {:noreply, assign_listing(socket, state, rows, sources, total_entries, pages)}
    end
  end

  @impl true
  # The toolbar and `<.pagination>`'s rows-per-page select both post under
  # `filters`. A key the posting form did not carry keeps its current value.
  # The URL keeps this screen's `page_size` key; the select posts `perPage`.
  def handle_event("filter", params, socket) do
    current = socket.assigns.state
    filters = Map.get(params, "filters", %{})

    state = %{
      current
      | search: Map.get(filters, "search", current.search),
        source: Map.get(filters, "source", current.source),
        page_size: page_size(Map.get(filters, "perPage"), current.page_size),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/system/menu-inspector?#{state_to_params(state)}")
  end

  defp visible_rows(socket, state) do
    all_rows = inspect_rows(socket.assigns.current_scope)

    rows =
      all_rows
      |> filter_by_source(state.source)
      |> search_rows(state.search)

    {rows, available_sources(all_rows)}
  end

  defp assign_listing(socket, state, rows, sources, total_entries, pages) do
    entries = Enum.slice(rows, (state.page - 1) * state.page_size, state.page_size)

    socket
    |> assign(:sources, sources)
    |> assign(:state, state)
    |> assign(:filters_form, filters_form(state))
    |> assign(:total_entries, total_entries)
    |> assign(:items_page, %{
      page: state.page,
      page_size: state.page_size,
      total_entries: total_entries,
      total_pages: pages
    })
    |> stream(:items, entries, reset: true)
  end

  defp default_state do
    %{search: "", source: "", page: 1, page_size: @default_page_size}
  end

  defp empty_page do
    %{page: 1, page_size: @default_page_size, total_entries: 0, total_pages: 0}
  end

  defp filters_form(state) do
    to_form(
      %{
        "search" => state.search,
        "source" => state.source,
        "perPage" => Integer.to_string(state.page_size)
      },
      as: :filters
    )
  end

  defp inspect_rows(current_scope) do
    Enum.map(Menu.items(), fn item ->
      %{
        id: item.id,
        label: item.label,
        parent: item.parent,
        kind: if(Menu.Item.container?(item), do: "container", else: "leaf"),
        capability: item.capability,
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

  defp state_from_params(params) do
    source = Map.get(params, "source", "")

    %{
      search: Map.get(params, "search", ""),
      source: if(source == "all", do: "", else: source),
      page: to_int(Map.get(params, "page"), 1),
      page_size:
        page_size(Map.get(params, "page_size") || Map.get(params, "perPage"), @default_page_size)
    }
  end

  defp state_to_params(state) do
    params = %{"page" => state.page, "page_size" => state.page_size}
    params = if state.search != "", do: Map.put(params, "search", state.search), else: params

    if state.source != "" and state.source != "all" do
      Map.put(params, "source", state.source)
    else
      params
    end
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total, page_size), do: div(total + page_size - 1, page_size)

  defp page_size(value, default) do
    parsed = to_int(value, default)
    if parsed in @page_sizes, do: parsed, else: default
  end

  defp to_int(nil, default), do: default

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(value, _default) when is_integer(value) and value > 0, do: value
  defp to_int(_value, default), do: default
end
