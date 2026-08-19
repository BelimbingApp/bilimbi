defmodule Bilimbi.Base.System.Web.MenuInspectorLive do
  @moduledoc """
  Diagnostic listing of every contributed menu item.

  Ports Belimbing's `app/Base/System/Livewire/MenuInspector/Index.php`.
  Belimbing also shows source module/file, a condition column, and an
  extension kind. `Bilimbi.Base.Menu.Item` does not carry those fields;
  this page lists id, label, parent, container vs leaf, capability, route,
  whether the route is served, and whether the current actor is allowed
  the capability. Search covers those strings. There is no extension filter
  while no Extension is installed.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.UI.Nav

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Menu Inspector")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    state = %{socket.assigns.state | search: Map.get(params, "search", ""), page: 1}
    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/system/menu-inspector?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    rows =
      socket.assigns.current_scope
      |> inspect_rows()
      |> search_rows(state.search)

    total_entries = length(rows)
    total_pages = total_pages(total_entries)
    page = clamp_page(state.page, total_pages)
    entries = Enum.slice(rows, (page - 1) * @page_size, @page_size)

    socket
    |> assign(:state, %{state | page: page})
    |> assign(:total_entries, total_entries)
    |> assign(:total_pages, total_pages)
    |> stream(:items, entries, reset: true)
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
        served?: is_nil(item.route) or Nav.served?(item.route),
        allowed?: is_nil(item.capability) or allowed?(current_scope, item.capability)
      }
    end)
  end

  defp search_rows(rows, ""), do: rows

  defp search_rows(rows, search) do
    needle = String.downcase(search)

    Enum.filter(rows, fn row ->
      Enum.any?(
        [row.id, row.label, row.parent, row.capability, row.route],
        fn
          nil -> false
          value -> String.contains?(String.downcase(value), needle)
        end
      )
    end)
  end

  defp state_from_params(params) do
    %{search: Map.get(params, "search", ""), page: to_int(Map.get(params, "page"), 1)}
  end

  defp state_to_params(state) do
    %{"search" => state.search, "page" => state.page}
  end

  defp clamp_page(_page, 0), do: 1
  defp clamp_page(page, total_pages) when page > total_pages, do: total_pages
  defp clamp_page(page, _total_pages), do: page

  defp total_pages(0), do: 0
  defp total_pages(total), do: div(total + @page_size - 1, @page_size)

  defp to_int(nil, default), do: default

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(value, _default) when is_integer(value) and value > 0, do: value
  defp to_int(_value, default), do: default

  defp item_noun(1), do: "item"
  defp item_noun(_count), do: "items"
end
