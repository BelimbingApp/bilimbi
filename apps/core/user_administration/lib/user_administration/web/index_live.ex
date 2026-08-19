defmodule Bilimbi.Core.UserAdministration.Web.IndexLive do
  @moduledoc """
  Tenant-scoped adapter for the bounded Users administration index.

  The adapter normalizes URL and form state before calling the strict read
  facade. Archived company affiliations are presented as read-only.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Core.User
  alias Bilimbi.Core.UserAdministration
  alias Bilimbi.Core.UserAdministration.Options

  @page_sizes [25, 50, 100, 300]
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
     |> assign(:page_sizes, @page_sizes)
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

  def handle_event("delete", %{"id" => raw_id}, socket) do
    scope = socket.assigns.current_scope.scope
    actor_id = socket.assigns.current_scope.user["user_id"]

    cond do
      not allowed?(socket.assigns.current_scope, "admin.user.delete") ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete users.")}

      match?({id, ""} when id == actor_id, Integer.parse(to_string(raw_id))) ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}

      true ->
        with {user_id, ""} <- Integer.parse(to_string(raw_id)),
             %{} = entry <- Enum.find(socket.assigns.users_page.entries, &(&1.id == user_id)),
             :ok <- delete_listed_user(scope, entry) do
          {:noreply,
           socket
           |> put_flash(:info, "User deleted successfully.")
           |> load_page(socket.assigns.index_state)}
        else
          :error ->
            {:noreply, put_flash(socket, :error, "That user could not be deleted.")}

          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "That user no longer exists.")
             |> load_page(socket.assigns.index_state)}

          {:error, :company_not_found} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "That user cannot be deleted while their company is archived."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "That user could not be deleted.")}
        end
    end
  end

  defp delete_listed_user(_scope, %{company_archived: true}), do: {:error, :company_not_found}

  defp delete_listed_user(scope, entry) do
    User.delete_user(scope, entry.company_id, entry.id)
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

    cond do
      page.total_pages > 0 and state.page > page.total_pages ->
        clamped_state = %{state | page: page.total_pages}
        push_patch(socket, to: users_path(clamped_state))

      page.total_pages == 0 and state.page > 1 ->
        clamped_state = %{state | page: 1}
        push_patch(socket, to: users_path(clamped_state))

      true ->
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
    case positive_integer(value) do
      size when size in @page_sizes -> size
      _ -> 25
    end
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
end
