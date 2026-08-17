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

  # Belimbing also sorts by company name and by the two counts. Authz's
  # administration query does not offer those, and a header that sorts by
  # nothing is worse than one that is absent, so this offers what the API
  # accepts. Tracked on #99.
  @sortable ~w(name code is_system created_at)
  @page_sizes [25, 50, 100]

  @impl true
  def mount(_params, _session, socket) do
    # Computed here rather than through a local `allowed?/2`: three copies of
    # that helper already exist (`user_auth.ex`, `employee/web/capabilities.ex`,
    # `ui/nav.ex`) and a fourth would be one more place for the capability rule
    # to drift. Tracked on #223.
    {:ok,
     assign(socket,
       page_title: "Roles",
       can_create?: "admin.authz.role.create" in socket.assigns.current_scope.capabilities
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | search: search, page: 1})}
  end

  # The shared `<.table>` pushes the column as `phx-value-sort`, so the param is
  # "sort" rather than the "column" this screen used while it hand-rolled its
  # own header buttons.
  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    state = socket.assigns.state
    column = String.to_existing_atom(column)

    direction =
      if state.sort_by == column and state.sort_dir == :asc, do: :desc, else: :asc

    {:noreply, push_state(socket, %{state | sort_by: column, sort_dir: direction, page: 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  # The URL carries the whole view state, so a filtered, sorted page is a link
  # somebody can send to a colleague -- and the back button works.
  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/roles?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_roles(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    # `Page.page` echoes the request, so an out-of-range page returns empty with
    # a real `total_pages` -- rendered as-is that is a dead end with no rows, no
    # empty-state text and no pager. Land on the last real page instead.
    if beyond_last_page?(page) do
      load(socket, %{state | page: page.total_pages})
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> stream(:roles, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(page),
    do: page.total_pages > 0 and page.page > page.total_pages

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: if(Map.get(params, "sort_dir") == "desc", do: :desc, else: :asc),
      page: to_int(Map.get(params, "page"), 1),
      page_size: page_size_from(Map.get(params, "page_size"))
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "sort_by" => state.sort_by,
      "sort_dir" => state.sort_dir,
      "page" => state.page,
      "page_size" => state.page_size
    }
  end

  # A hand-edited URL must not crash the page or reach the query with something
  # the API would reject.
  defp sort_by_from(value) when value in @sortable, do: String.to_existing_atom(value)
  defp sort_by_from(_value), do: :name

  defp page_size_from(value) do
    case to_int(value, 25) do
      size when size in @page_sizes -> size
      _ -> 25
    end
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

  defp nilify(""), do: nil
  defp nilify(value), do: value

  defp scope_label(%{is_system: true}), do: "System"
  defp scope_label(%{company_id: nil}), do: "Unowned"
  defp scope_label(_role), do: "Custom"

  defp scope_kind(%{is_system: true}), do: :neutral
  defp scope_kind(%{company_id: nil}), do: :warning
  defp scope_kind(_role), do: :success
end
