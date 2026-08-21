defmodule Bilimbi.Core.User.Web.DatabaseQueriesLive.Index do
  @moduledoc """
  User-defined SQL database queries rendered as browsable, sortable pages.

  Ports Belimbing's `app/Base/Database/Livewire/Queries/Index.php`.
  Each user manages their own queries.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.User

  @sortable ~w(name description created_at updated_at)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Database Queries")
     |> assign(:active_nav, "admin.system.database-query")
     |> assign(:search, "")
     |> assign(:sort_by, "updated_at")
     |> assign(:sort_dir, :desc)
     |> assign(:page, 1)
     |> assign(:per_page, 25)
     |> load_queries()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = Map.get(params, "search", socket.assigns.search)

    sort_by =
      if Map.get(params, "sort_by") in @sortable,
        do: params["sort_by"],
        else: socket.assigns.sort_by

    sort_dir =
      if Map.get(params, "sort_dir") in ["asc", "desc"],
        do: String.to_existing_atom(params["sort_dir"]),
        else: socket.assigns.sort_dir

    page = to_integer(Map.get(params, "page"), socket.assigns.page)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> assign(:page, page)
     |> load_queries()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> load_queries()}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @sortable do
    sort_dir =
      if socket.assigns.sort_by == column do
        if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
      else
        default_sort_dir(column)
      end

    {:noreply,
     socket
     |> assign(:sort_by, column)
     |> assign(:sort_dir, sort_dir)
     |> assign(:page, 1)
     |> load_queries()}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, to_integer(page, 1))
     |> load_queries()}
  end

  @impl true
  def handle_event("duplicate", %{"id" => id_str}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)
      query_id = to_integer(id_str, 0)

      case User.duplicate_database_query(scope, user_id, query_id) do
        {:ok, duplicate} ->
          {:noreply,
           socket
           |> put_flash(:info, "Query duplicated.")
           |> push_navigate(to: ~p"/admin/system/database-queries/#{duplicate.slug}")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not duplicate query.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id_str}, socket) do
    if allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)
      query_id = to_integer(id_str, 0)

      case User.delete_database_query(scope, user_id, query_id) do
        {:ok, _deleted} ->
          {:noreply,
           socket
           |> put_flash(:info, "Query deleted.")
           |> load_queries()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not delete query.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
  end

  defp default_sort_dir(col) when col in ["created_at", "updated_at"], do: :desc
  defp default_sort_dir(_col), do: :asc

  defp load_queries(socket) do
    scope = socket.assigns.current_scope.scope
    user_id = current_user_id(socket.assigns.current_scope)

    opts = [
      search: socket.assigns.search,
      sort_by: socket.assigns.sort_by,
      sort_dir: socket.assigns.sort_dir
    ]

    all_queries =
      case User.list_database_queries(scope, user_id, opts) do
        {:ok, queries} -> queries
        {:error, _} -> []
      end

    total_count = length(all_queries)
    per_page = socket.assigns.per_page
    total_pages = max(ceil(total_count / per_page), 1)
    page = min(socket.assigns.page, total_pages)
    offset = (page - 1) * per_page
    paginated_queries = Enum.slice(all_queries, offset, per_page)

    socket
    |> assign(:queries, paginated_queries)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:page, page)
  end

  defp to_integer(nil, default), do: default
  defp to_integer(val, _default) when is_integer(val), do: val

  defp to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end
end
