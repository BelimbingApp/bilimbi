defmodule Bilimbi.Core.UserAdministration.Web.IndexLive do
  @moduledoc """
  Tenant-scoped adapter for the bounded Users administration index.

  The adapter normalizes URL and form state before calling the strict read
  facade. Account deletion remains a public Core User command and archived
  company affiliations are presented as read-only.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.User
  alias Bilimbi.Core.UserAdministration
  alias Bilimbi.Core.UserAdministration.Options

  @page_sizes [10, 25, 50, 100]
  @sorts %{
    "name" => :name,
    "email" => :email,
    "company_name" => :company_name,
    "created_at" => :created_at
  }
  @initial_directions %{"created_at" => "desc"}
  @maximum_search_bytes 255

  embed_templates("index_live/*")

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:active_nav, "admin.user")
     |> assign(:role_options, role_options(scope))
     |> stream_configure(:users, dom_id: &"user-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def render(assigns), do: index(assigns)

  @impl true
  def handle_event("filters", params, socket) do
    filters = Map.get(params, "filters", %{})

    state =
      socket.assigns.index_state
      |> Map.put(:search, normalize_search(Map.get(filters, "search", "")))
      |> Map.put(:role_ids, normalize_role_ids(Map.get(filters, "roleIds", [])))
      |> Map.put(
        :page_size,
        normalize_page_size(Map.get(filters, "perPage", socket.assigns.index_state.page_size))
      )
      |> Map.put(:page, 1)

    {:noreply, push_patch(socket, to: users_path(state))}
  end

  def handle_event("sort", %{"sort" => requested_sort}, socket) do
    {:noreply,
     push_patch(socket, to: users_path(next_sort(socket.assigns.index_state, requested_sort)))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state =
      Map.put(
        socket.assigns.index_state,
        :page,
        bounded_page(page, socket.assigns.users_page)
      )

    {:noreply, push_patch(socket, to: users_path(state))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user_id = positive_integer(id)

    cond do
      user_id == socket.assigns.current_scope.user["user_id"] ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      is_integer(user_id) ->
        delete_user(socket, user_id)

      true ->
        {:noreply, put_flash(socket, :error, "That user could not be deleted.")}
    end
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:sort, :string, required: true)
  attr(:sort_by, :string, required: true)
  attr(:sort_dir, :string, required: true)

  def sortable_heading(assigns) do
    ~H"""
    <th scope="col" class="px-4 py-2.5 text-xs font-semibold uppercase tracking-wider text-ink-subtle">
      <button
        id={@id}
        type="button"
        phx-click="sort"
        phx-value-sort={@sort}
        class="inline-flex items-center gap-1 rounded text-left transition hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25"
      >
        {@label}
        <.icon
          name={sort_icon(@sort, @sort_by, @sort_dir)}
          class={["size-3.5", @sort == @sort_by && "text-action"]}
        />
      </button>
    </th>
    """
  end

  defp delete_user(socket, user_id) do
    if allowed?(socket.assigns.current_scope, "admin.user.delete") do
      scope = socket.assigns.current_scope.scope

      case User.get_tenant_user(scope, user_id) do
        {:ok, user} -> delete_visible_user(socket, user)
        {:error, :user_not_found} -> deletion_race(socket)
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}
    end
  end

  defp delete_visible_user(socket, user) do
    case User.delete_user(socket.assigns.current_scope.scope, user.company_id, user.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "User deleted successfully.")
         |> load_page(socket.assigns.index_state)}

      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That user cannot be deleted while their company is archived.")
         |> load_page(socket.assigns.index_state)}

      {:error, :user_not_found} ->
        deletion_race(socket)
    end
  end

  defp deletion_race(socket) do
    {:noreply,
     socket
     |> put_flash(:error, "That user no longer exists.")
     |> load_page(socket.assigns.index_state)}
  end

  defp load_page(socket, state) do
    page =
      UserAdministration.list_users(socket.assigns.current_scope.scope,
        search: state.search,
        role_ids: state.role_ids,
        sort_by: Map.fetch!(@sorts, state.sort_by),
        sort_dir: direction_atom(state.sort_dir),
        page: state.page,
        page_size: state.page_size
      )

    socket
    |> assign(:users_page, page)
    |> assign(:index_state, state)
    |> assign(
      :filters_form,
      to_form(
        %{
          "search" => state.search,
          "roleIds" => Enum.map(state.role_ids, &Integer.to_string/1),
          "perPage" => state.page_size
        },
        as: :filters
      )
    )
    |> stream(:users, page.entries, reset: true)
  end

  defp state_from_params(params) do
    sort_by = normalize_sort(Map.get(params, "sortBy"))

    %{
      search: normalize_search(Map.get(params, "search", "")),
      role_ids: normalize_role_ids(Map.get(params, "roleIds", [])),
      page: normalize_page(Map.get(params, "page")),
      page_size: normalize_page_size(Map.get(params, "perPage")),
      sort_by: sort_by,
      sort_dir: normalize_direction(Map.get(params, "sortDir"), sort_by)
    }
  end

  defp next_sort(state, requested_sort) do
    sort_by = normalize_sort(requested_sort)

    %{
      state
      | page: 1,
        sort_by: sort_by,
        sort_dir:
          if(state.sort_by == sort_by,
            do: flip_direction(state.sort_dir),
            else: default_direction(sort_by)
          )
    }
  end

  defp users_path(state) do
    query = %{
      search: state.search,
      roleIds: state.role_ids,
      page: state.page,
      perPage: state.page_size,
      sortBy: state.sort_by,
      sortDir: state.sort_dir
    }

    ~p"/users?#{query}"
  end

  defp role_options(scope) do
    scope
    |> Authz.list_roles(page: 1, page_size: 100, sort_by: :name, sort_dir: :asc)
    |> Map.fetch!(:entries)
    |> Enum.map(&{&1.name, &1.id})
  end

  defp page_size_options, do: Enum.map(@page_sizes, &{"#{&1} rows", &1})

  defp normalize_search(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {graphemes, bytes} ->
      next_bytes = bytes + byte_size(grapheme)

      if next_bytes <= @maximum_search_bytes do
        {:cont, {[grapheme | graphemes], next_bytes}}
      else
        {:halt, {graphemes, bytes}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp normalize_search(_value), do: ""

  defp normalize_role_ids(values) do
    values
    |> List.wrap()
    |> Enum.map(&positive_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(100)
  end

  defp normalize_sort(value) when is_map_key(@sorts, value), do: value
  defp normalize_sort(_value), do: "name"

  defp normalize_direction(value, _sort_by) when value in ["asc", "desc"], do: value
  defp normalize_direction(_value, sort_by), do: default_direction(sort_by)

  defp default_direction(sort_by), do: Map.get(@initial_directions, sort_by, "asc")
  defp flip_direction("asc"), do: "desc"
  defp flip_direction(_direction), do: "asc"

  defp direction_atom("desc"), do: :desc
  defp direction_atom(_direction), do: :asc

  defp normalize_page(value) do
    case positive_integer(value) do
      nil -> 1
      page -> min(page, Options.max_page())
    end
  end

  defp normalize_page_size(value) do
    requested = positive_integer(value) || 25
    Enum.find(@page_sizes, List.last(@page_sizes), &(&1 >= requested))
  end

  defp bounded_page(value, page) do
    requested = normalize_page(value)
    requested |> min(max(page.total_pages, 1)) |> max(1)
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp initials(_name), do: "?"

  defp format_created(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d")
  defp format_created(_value), do: "—"

  defp sort_icon(sort, sort, "asc"), do: "hero-chevron-up"
  defp sort_icon(sort, sort, "desc"), do: "hero-chevron-down"
  defp sort_icon(_sort, _sort_by, _sort_dir), do: "hero-chevron-up-down"

  defp page_summary(%{total_entries: 0}), do: "No results"

  defp page_summary(%{entries: [], total_entries: total_entries}) do
    "No results on this page · #{total_entries} total"
  end

  defp page_summary(%{page: page, page_size: page_size, total_entries: total_entries}) do
    first = (page - 1) * page_size + 1
    last = min(page * page_size, total_entries)
    "Showing #{first}–#{last} of #{total_entries}"
  end

  defp page_position(%{total_pages: 0}), do: "Page 0 of 0"

  defp page_position(%{page: page, total_pages: total_pages}) do
    "Page #{page} of #{total_pages}"
  end
end
