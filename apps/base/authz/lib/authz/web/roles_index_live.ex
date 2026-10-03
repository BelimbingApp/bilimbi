defmodule Bilimbi.Base.Authz.Web.RolesIndexLive do
  @moduledoc """
  Authorization roles, bounded and searchable.

  Ports Belimbing's `app/Base/Authz/Livewire/Roles/Index.php`. The visibility
  rule there — system roles, plus custom roles whose owning company is in the
  current tenant and not soft-deleted — lives in `Authz.list_roles/2`, not
  here. A LiveView that rebuilt it would be a second copy of a tenancy
  boundary, which is the kind of duplicate that drifts silently and leaks
  another tenant's roles when it does.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # Belimbing also sorts by company name and by the two counts. Authz's
  # administration query does not offer those, and a header that sorts by
  # nothing is worse than one that is absent, so this offers what the API
  # accepts. Tracked on #99. Every column opens ascending. An unrecognised
  # rows-per-page value falls back to 25, including one the toolbar posts;
  # the URL key stays `page_size`.
  @list ListState.spec!(
          sortable: %{name: :asc, code: :asc, is_system: :asc, created_at: :asc},
          default_sort: :name,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "page_size",
          invalid_page_size: :default
        )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Roles",
       can_create?: allowed?(socket.assigns.current_scope, "admin.authz.role.create"),
       reach_caution?: reach_caution?(socket)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  def handle_event("search", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  # The shared `<.table>` pushes the column as `phx-value-sort`, so the param is
  # "sort" rather than the "column" this screen used while it hand-rolled its
  # own header buttons.
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

  # The URL carries the whole view state, so a filtered, sorted page is a link
  # somebody can send to a colleague -- and the back button works.
  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/roles?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_roles(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    # `Page.page` echoes the request, so an out-of-range page returns empty with
    # a real `total_pages` -- rendered as-is that is a dead end with no rows, no
    # empty-state text and no pager. Land on the last real page instead.
    corrected = ListState.clamp_to_last_page(state, page)

    if corrected.page != state.page do
      load(socket, corrected)
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:filters_form, ListState.filters_form(state))
      |> stream(:roles, page.entries, reset: true)
    end
  end

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  defp scope_label(%{is_system: true}), do: "System"
  defp scope_label(%{company_id: nil}), do: "Unowned"
  defp scope_label(_role), do: "Custom"

  defp scope_kind(%{is_system: true}), do: :neutral
  defp scope_kind(%{company_id: nil}), do: :warning
  defp scope_kind(_role), do: :success

  # The listed roles are the same for every scope, but `Authz` widens each row's
  # Principals count for the platform-operator scope to assignments attached to
  # no company (`Administration.company_visibility/2`). The caution names that
  # widening where the counts are read; it changes nothing about what is counted.
  defp reach_caution?(socket) do
    Scope.platform_operator?(socket.assigns.current_scope.scope)
  end
end
