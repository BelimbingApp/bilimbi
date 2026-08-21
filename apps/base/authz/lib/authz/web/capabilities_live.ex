defmodule Bilimbi.Base.Authz.Web.CapabilitiesLive do
  @moduledoc """
  Catalog of registered authorization capabilities and their contributing modules.

  Ports Belimbing's `app/Base/Authz/Livewire/Capabilities/Index.php` and
  `resources/core/views/livewire/admin/authz/capabilities/index.blade.php`.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz

  @sortable ~w(key domain resource action module)

  @impl true
  def mount(_params, _session, socket) do
    domains = Authz.capability_domains()

    {:ok,
     socket
     |> assign(:page_title, "Capabilities")
     |> assign(:domains, domains)}
  end

  @page_sizes [25, 50, 100, 300]

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    current = socket.assigns.state
    per_page = get_in(params, ["filters", "perPage"]) || Map.get(params, "perPage")

    state = %{
      current
      | search: Map.get(params, "search", current.search),
        domain:
          member_or_blank(Map.get(params, "domain", current.domain), socket.assigns.domains),
        page_size: page_size_from(per_page, current.page_size),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    state = socket.assigns.state
    column = String.to_existing_atom(column)

    direction =
      cond do
        state.sort_by != column -> :asc
        state.sort_dir == :asc -> :desc
        true -> :asc
      end

    {:noreply, push_state(socket, %{state | sort_by: column, sort_dir: direction, page: 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/capabilities?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_capabilities(
        search: nilify(state.search),
        domain: nilify(state.domain),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    if beyond_last_page?(page) do
      load(socket, %{state | page: page.total_pages})
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(
        :filters_form,
        to_form(%{"perPage" => Integer.to_string(state.page_size)}, as: :filters)
      )
      |> stream(:capabilities, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(page),
    do: page.total_pages > 0 and page.page > page.total_pages

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      domain: Map.get(params, "domain", ""),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(params),
      page: to_int(Map.get(params, "page"), 1),
      page_size: page_size_from(Map.get(params, "per_page"), 25)
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "domain" => state.domain,
      "sort_by" => state.sort_by,
      "sort_dir" => state.sort_dir,
      "page" => state.page,
      "per_page" => state.page_size
    }
  end

  defp page_size_from(value, fallback) do
    case to_int(value, fallback) do
      size when size in @page_sizes -> size
      _ -> fallback
    end
  end

  defp member_or_blank(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: ""
  end

  defp member_or_blank(_value, _allowed), do: ""

  defp sort_by_from(value) when value in @sortable, do: String.to_existing_atom(value)
  defp sort_by_from(_value), do: :key

  defp sort_dir_from(%{"sort_dir" => "asc"}), do: :asc
  defp sort_dir_from(%{"sort_dir" => "desc"}), do: :desc
  defp sort_dir_from(_params), do: :asc

  defp to_int(nil, default), do: default

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(value, _default) when is_integer(value) and value > 0, do: value
  defp to_int(_value, default), do: default

  defp nilify(""), do: nil
  defp nilify(value), do: value
end
