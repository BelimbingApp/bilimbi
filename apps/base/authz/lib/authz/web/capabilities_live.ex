defmodule Bilimbi.Base.Authz.Web.CapabilitiesLive do
  @moduledoc """
  Catalog of registered authorization capabilities and their contributing modules.

  Ports Belimbing's `app/Base/Authz/Livewire/Capabilities/Index.php` and
  `resources/core/views/livewire/admin/authz/capabilities/index.blade.php`.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # Every column opens ascending. `domain` in the URL is kept as posted and
  # checked against the registered domains only when the toolbar submits it,
  # which is what a hand-edited link already did. The URL key is `per_page`.
  @list ListState.spec!(
          sortable: %{key: :asc, domain: :asc, resource: :asc, action: :asc, module: :asc},
          default_sort: :key,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "per_page",
          filters: [domain: {:string, ""}]
        )

  @impl true
  def mount(_params, _session, socket) do
    domains = Authz.capability_domains()

    {:ok,
     socket
     |> assign(:page_title, "Capabilities")
     |> assign(:domains, domains)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    posted = filters(params)

    # The page-size form posts `perPage` alone. Re-check the current domain
    # anyway: a hand-edited URL can name a domain that is not registered, and
    # the next toolbar submission drops it.
    domain =
      member_or_blank(
        Map.get(posted, "domain", socket.assigns.state.filters.domain),
        socket.assigns.domains
      )

    {:noreply,
     push_state(
       socket,
       ListState.apply_filters(socket.assigns.state, Map.put(posted, "domain", domain))
     )}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) do
    state = socket.assigns.state

    case ListState.next_sort(state, column) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_state(socket, next)}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, ListState.put_page(socket.assigns.state, page))}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/capabilities?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_capabilities(
        search: Params.blank_to_nil(state.search),
        domain: Params.blank_to_nil(state.filters.domain),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    corrected = ListState.clamp_to_last_page(state, page)

    if corrected.page != state.page do
      load(socket, corrected)
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:filters_form, ListState.filters_form(state))
      |> stream(:capabilities, page.entries, reset: true)
    end
  end

  # Anything outside the registered domains becomes "no filter" rather than
  # reaching the query as a domain that does not exist.
  defp member_or_blank(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: ""
  end

  defp member_or_blank(_value, _allowed), do: ""

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}
end
