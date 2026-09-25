defmodule Bilimbi.Core.User.Web.DatabaseQueriesLive.Index do
  @moduledoc """
  User-defined SQL database queries rendered as browsable, sortable pages.

  Ports Belimbing's `app/Base/Database/Livewire/Queries/Index.php`.
  Each user manages their own queries.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User

  @sortable ~w(name description created_at updated_at)
  @page_sizes [25, 50, 100, 300]
  @default_page_size 25

  @impl true
  def mount(_params, _session, socket) do
    state = default_state()

    {:ok,
     socket
     |> assign(:page_title, "Database Queries")
     |> assign(:active_nav, "admin.system.database-query")
     |> assign(:page_sizes, @page_sizes)
     |> assign(:pending_delete, nil)
     |> assign(:state, state)
     |> assign(:queries, [])
     |> assign(:queries_page, empty_page())
     |> assign(:filters_form, filters_form(state))
     |> assign_list_fields(state)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    requested = state_from_params(params)
    socket = socket |> assign(:state, requested) |> load_queries()
    {:noreply, maybe_clamp_patch(socket, requested.page)}
  end

  @impl true
  # The toolbar posts `search`. `<.pagination>` posts only `perPage` on this
  # same event. A key the posting form did not carry keeps its current value.
  # The URL keeps `page_size`.
  def handle_event("search", params, socket) do
    filters = Map.get(params, "filters", %{})
    state = socket.assigns.state

    state = %{
      state
      | search: Map.get(filters, "search", state.search),
        page_size: page_size(Map.get(filters, "perPage"), state.page_size),
        page: 1
    }

    {:noreply, push_patch(socket, to: index_path(state))}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    sort_queries(socket, column)
  end

  def handle_event("sort", %{"column" => column}, socket) when column in @sortable do
    sort_queries(socket, column)
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    state = %{socket.assigns.state | page: to_integer(page, 1)}
    {:noreply, push_patch(socket, to: index_path(state))}
  end

  @impl true
  def handle_event("duplicate", %{"id" => id_str}, socket) do
    if operator?(socket) and
         allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)
      query_id = to_integer(id_str, 0)

      case User.duplicate_database_query(scope, user_id, query_id) do
        {:ok, duplicate} ->
          {:noreply,
           socket
           |> put_flash(:success, "Query duplicated.")
           |> push_navigate(to: ~p"/admin/system/database-queries/#{duplicate.slug}")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not duplicate query.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
  end

  # Deleting confirms through the shared dialog: the request holds the listed
  # query whose consequence the dialog states, and `delete` acts on that held
  # query rather than on a client-supplied id, so what was confirmed is what
  # runs.
  @impl true
  def handle_event("request_delete", %{"id" => id_str}, socket) do
    cond do
      not can_modify?(socket) ->
        modify_forbidden(socket)

      query = Enum.find(socket.assigns.queries, &(&1.id == to_integer(id_str, 0))) ->
        {:noreply, socket |> clear_flash() |> assign(:pending_delete, query)}

      true ->
        {:noreply, socket |> put_flash(:error, "That query no longer exists.") |> load_queries()}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("delete", _params, socket) do
    cond do
      not can_modify?(socket) ->
        modify_forbidden(socket)

      is_nil(socket.assigns.pending_delete) ->
        {:noreply, socket}

      true ->
        query = socket.assigns.pending_delete
        socket = assign(socket, :pending_delete, nil)
        scope = socket.assigns.current_scope.scope
        user_id = current_user_id(socket.assigns.current_scope)

        case User.delete_database_query(scope, user_id, query.id) do
          {:ok, _deleted} ->
            previous_page = socket.assigns.state.page

            {:noreply,
             socket
             |> load_queries()
             |> maybe_clamp_patch(previous_page)
             |> put_flash(:success, "Query “#{query.name}” was deleted.")}

          {:error, :not_found} ->
            {:noreply,
             socket |> put_flash(:error, "That query no longer exists.") |> load_queries()}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Query “#{query.name}” was not deleted. Reload the page and try again."
             )}
        end
    end
  end

  defp can_modify?(socket) do
    operator?(socket) and
      allowed?(socket.assigns.current_scope, "admin.system.database-table.edit")
  end

  defp modify_forbidden(socket) do
    {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
  end

  defp default_sort_dir(col) when col in ["created_at", "updated_at"], do: :desc
  defp default_sort_dir(_col), do: :asc

  # #650: the console is operator-only. Mount gates it, and every mutation
  # repeats the operator proof captured in that mount's scope. A changed tenant
  # marker is observed by a fresh authenticated mount.
  defp operator?(socket) do
    case socket.assigns.current_scope do
      %{scope: %Scope{} = scope} -> Scope.platform_operator?(scope)
      _ -> false
    end
  end

  defp sort_queries(socket, column) do
    state = socket.assigns.state

    sort_dir =
      if state.sort_by == column do
        if state.sort_dir == :asc, do: :desc, else: :asc
      else
        default_sort_dir(column)
      end

    state = %{state | sort_by: column, sort_dir: sort_dir, page: 1}
    {:noreply, push_patch(socket, to: index_path(state))}
  end

  defp load_queries(socket) do
    state = socket.assigns.state
    scope = socket.assigns.current_scope.scope
    user_id = current_user_id(socket.assigns.current_scope)

    opts = [
      search: state.search,
      sort_by: state.sort_by,
      sort_dir: state.sort_dir
    ]

    all_queries =
      case User.list_database_queries(scope, user_id, opts) do
        {:ok, queries} -> queries
        {:error, _} -> []
      end

    total_count = length(all_queries)
    total_pages = total_pages(total_count, state.page_size)

    page =
      cond do
        total_pages == 0 -> 1
        state.page > total_pages -> total_pages
        true -> state.page
      end

    state = %{state | page: page}
    offset = (page - 1) * state.page_size

    socket
    |> assign(:state, state)
    |> assign_list_fields(state)
    |> assign(:queries, Enum.slice(all_queries, offset, state.page_size))
    |> assign(:total_count, total_count)
    |> assign(:queries_page, %{
      page: page,
      page_size: state.page_size,
      total_entries: total_count,
      total_pages: total_pages
    })
    |> assign(:filters_form, filters_form(state))
  end

  defp assign_list_fields(socket, state) do
    socket
    |> assign(:search, state.search)
    |> assign(:sort_by, state.sort_by)
    |> assign(:sort_dir, state.sort_dir)
    |> assign(:page, state.page)
    |> assign(:per_page, state.page_size)
  end

  defp maybe_clamp_patch(socket, requested_page) do
    if socket.assigns.state.page == requested_page do
      socket
    else
      push_patch(socket, to: index_path(socket.assigns.state))
    end
  end

  defp default_state do
    %{
      search: "",
      sort_by: "updated_at",
      sort_dir: :desc,
      page: 1,
      page_size: @default_page_size
    }
  end

  defp empty_page do
    %{page: 1, page_size: @default_page_size, total_entries: 0, total_pages: 0}
  end

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(Map.get(params, "sort_dir")),
      page: to_integer(Map.get(params, "page"), 1),
      page_size: page_size(Map.get(params, "page_size") || Map.get(params, "perPage"))
    }
  end

  defp index_path(state) do
    query =
      %{
        "search" => state.search,
        "sort_by" => state.sort_by,
        "sort_dir" => Atom.to_string(state.sort_dir),
        "page" => state.page,
        "page_size" => state.page_size
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/admin/system/database-queries?#{query}"
  end

  defp filters_form(state) do
    to_form(
      %{"search" => state.search, "perPage" => Integer.to_string(state.page_size)},
      as: :filters
    )
  end

  defp sort_by_from(value) when value in @sortable, do: value
  defp sort_by_from(_value), do: "updated_at"

  defp sort_dir_from("asc"), do: :asc
  defp sort_dir_from("desc"), do: :desc
  defp sort_dir_from(_value), do: :desc

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total, page_size), do: ceil(total / page_size)

  defp page_size(value, default \\ @default_page_size) do
    parsed = to_integer(value, default)
    if parsed in @page_sizes, do: parsed, else: default
  end

  defp to_integer(nil, default), do: default
  defp to_integer(val, _default) when is_integer(val) and val > 0, do: val
  defp to_integer(val, default) when is_integer(val), do: default

  defp to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} when int > 0 -> int
      _invalid -> default
    end
  end
end
