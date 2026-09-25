defmodule Bilimbi.Core.User.Web.DatabaseQueriesLive.Show do
  @moduledoc """
  Show and edit page for a single database query.

  Ports Belimbing's `app/Base/Database/Livewire/Queries/Show.php`.
  Supports natural language prompt, SQL editing, dynamic named parameter inputs,
  read-only query execution, pagination, sorting, and user-scoped query management.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25

  # `run` is a write verb, so the write-handler guard treats `run_query` as
  # write-shaped. It is not: it calls `Database.execute_readonly/3`, which is
  # where read-only is enforced, and the route requires
  # `admin.system.database-table.list` — a read capability, correctly matched to
  # a read. There is no weaker capability for this handler to refuse.
  @write_guard_opt_out ~w(run_query)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_nav, "admin.system.database-query")
     |> assign(:reach_caution?, operator?(socket))
     |> assign(:is_new, false)
     |> assign(:pending_delete?, false)
     |> assign(:query, nil)
     |> assign(:name, "Untitled Query")
     |> assign(:description, "")
     |> assign(:prompt, "")
     |> assign(:sql_query, "")
     |> assign(:detected_params, [])
     |> assign(:param_values, %{})
     |> assign(:error, nil)
     |> assign(:results, nil)
     |> assign(:page_sizes, @page_sizes)
     |> assign(:result_page, 1)
     |> assign(:result_per_page, @default_page_size)
     |> assign(:results_filters_form, results_filters_form(@default_page_size))
     |> assign(:result_sort_by, nil)
     |> assign(:result_sort_dir, :asc)
     |> assign(:is_dirty, false)}
  end

  @impl true
  def handle_params(%{"slug" => "_new"}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "New Query")
     |> assign(:is_new, true)
     |> assign(:query, nil)
     |> assign(:name, "Untitled Query")
     |> assign(:description, "")
     |> assign(:prompt, "")
     |> assign(:sql_query, "")
     |> assign(:detected_params, [])
     |> assign(:param_values, %{})
     |> assign(:error, nil)
     |> assign(:results, nil)
     |> assign(:is_dirty, false)}
  end

  @impl true
  # A result-page change on the query already open stays on this process:
  # reloading the saved row here would discard SQL the operator has not saved.
  # The first visit, and any other slug, still loads the stored query.
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    if loaded_query?(socket, slug) do
      {:noreply, navigate_results(socket, params)}
    else
      load_saved_query(socket, slug, params)
    end
  end

  defp load_saved_query(socket, slug, params) do
    scope = socket.assigns.current_scope.scope
    user_id = current_user_id(socket.assigns.current_scope)

    case User.get_database_query(scope, user_id, slug) do
      {:ok, query} ->
        sql = query.sql_query || ""
        detected = Database.extract_named_parameters(sql)
        default_params = Map.new(detected, fn p -> {p, ""} end)

        page_size = result_page_size(params["page_size"] || params["perPage"])

        socket =
          socket
          |> assign(:page_title, query.name)
          |> assign(:is_new, false)
          |> assign(:query, query)
          |> assign(:name, query.name)
          |> assign(:description, query.description || "")
          |> assign(:prompt, query.prompt || "")
          |> assign(:sql_query, sql)
          |> assign(:detected_params, detected)
          |> assign(:param_values, default_params)
          |> assign(:error, nil)
          |> assign(:is_dirty, false)
          |> assign(:result_page, result_page(params["page"]))
          |> assign(:result_per_page, page_size)
          |> assign(:results_filters_form, results_filters_form(page_size))

        # Automatically execute query if SQL is non-empty
        {:noreply,
         if(String.trim(sql) != "",
           do: socket |> execute_query() |> clamp_result_page(),
           else: socket
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Query not found.")
         |> push_navigate(to: ~p"/admin/system/database-queries")}
    end
  end

  @impl true
  def handle_event("change_field", params, socket) when is_map(params) do
    name = Map.get(params, "name", socket.assigns.name)
    description = Map.get(params, "description", socket.assigns.description)
    prompt = Map.get(params, "prompt", socket.assigns.prompt)
    sql_query = Map.get(params, "sql_query", socket.assigns.sql_query)

    detected = Database.extract_named_parameters(sql_query)

    param_values =
      Enum.reduce(detected, socket.assigns.param_values, fn p, acc ->
        Map.put_new(acc, p, "")
      end)

    is_dirty =
      socket.assigns.is_new ||
        (socket.assigns.query &&
           (name != socket.assigns.query.name ||
              description != (socket.assigns.query.description || "") ||
              prompt != (socket.assigns.query.prompt || "") ||
              sql_query != (socket.assigns.query.sql_query || "")))

    {:noreply,
     socket
     |> assign(:name, name)
     |> assign(:description, description)
     |> assign(:prompt, prompt)
     |> assign(:sql_query, sql_query)
     |> assign(:detected_params, detected)
     |> assign(:param_values, param_values)
     |> assign(:is_dirty, is_dirty)}
  end

  @impl true
  def handle_event("change_param", params, socket) when is_map(params) do
    clean_params = Map.drop(params, ["_target", "_csrf_token"])
    param_values = Map.merge(socket.assigns.param_values, clean_params)
    {:noreply, assign(socket, :param_values, param_values)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    if operator?(socket) and
         allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)

      attrs = %{
        "name" => socket.assigns.name,
        "description" => socket.assigns.description,
        "prompt" => socket.assigns.prompt,
        "sql_query" => socket.assigns.sql_query
      }

      if socket.assigns.is_new do
        case User.create_database_query(scope, user_id, attrs) do
          {:ok, query} ->
            {:noreply,
             socket
             |> put_flash(:success, "Query saved.")
             |> push_navigate(to: ~p"/admin/system/database-queries/#{query.slug}")}

          {:error, changeset} ->
            error_msg = format_changeset_errors(changeset)
            {:noreply, assign(socket, :error, "Failed to save query: " <> error_msg)}
        end
      else
        case User.update_database_query(scope, user_id, socket.assigns.query.id, attrs) do
          {:ok, updated_query} ->
            {:noreply,
             socket
             |> assign(:query, updated_query)
             |> assign(:page_title, updated_query.name)
             |> assign(:is_dirty, false)
             |> put_flash(:success, "Query saved.")}

          {:error, changeset} ->
            error_msg = format_changeset_errors(changeset)
            {:noreply, assign(socket, :error, "Failed to save query: " <> error_msg)}
        end
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
  end

  @impl true
  def handle_event("run_query", _params, socket) do
    sql = String.trim(socket.assigns.sql_query || "")

    if sql == "" do
      {:noreply, assign(socket, error: "Please enter a SQL query first.", results: nil)}
    else
      {:noreply, show_result_page(socket, 1)}
    end
  end

  # The shared `<.table>` names the column in `phx-value-sort`.
  @impl true
  def handle_event("sort_results", %{"sort" => column}, socket) do
    sort_dir =
      if socket.assigns.result_sort_by == column do
        if socket.assigns.result_sort_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    {:noreply,
     socket
     |> assign(:result_sort_by, column)
     |> assign(:result_sort_dir, sort_dir)
     |> show_result_page(1)}
  end

  @impl true
  def handle_event("page_results", %{"page" => page}, socket) do
    {:noreply, show_result_page(socket, result_page(page))}
  end

  @impl true
  def handle_event("result_page_size", %{"results" => params}, socket) do
    size = result_page_size(params["perPage"])

    if persist_result_nav?(socket) do
      {:noreply, push_patch(socket, to: result_path(socket, page: 1, page_size: size))}
    else
      {:noreply,
       socket
       |> assign(:result_page, 1)
       |> assign(:result_per_page, size)
       |> assign(:results_filters_form, results_filters_form(size))
       |> execute_query()}
    end
  end

  def handle_event("result_page_size", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("duplicate", _params, socket) do
    if operator?(socket) and
         allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)

      if socket.assigns.query do
        case User.duplicate_database_query(scope, user_id, socket.assigns.query.id) do
          {:ok, duplicate} ->
            {:noreply,
             socket
             |> put_flash(:success, "Query duplicated.")
             |> push_navigate(to: ~p"/admin/system/database-queries/#{duplicate.slug}")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not duplicate query.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
  end

  @impl true
  # Deleting a saved query confirms through the shared dialog, which states
  # what is lost; `delete` runs only once a request is held. Discarding an
  # unsaved query loses nothing stored and needs no confirmation.
  def handle_event("request_delete", _params, socket) do
    cond do
      not can_modify?(socket) ->
        modify_forbidden(socket)

      socket.assigns.is_new || is_nil(socket.assigns.query) ->
        {:noreply, socket}

      true ->
        {:noreply, socket |> clear_flash() |> assign(:pending_delete?, true)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete?, false)}
  end

  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope.scope
    user_id = current_user_id(socket.assigns.current_scope)

    cond do
      not can_modify?(socket) ->
        modify_forbidden(socket)

      socket.assigns.is_new || is_nil(socket.assigns.query) ->
        {:noreply,
         socket
         |> put_flash(:info, "Query discarded.")
         |> push_navigate(to: ~p"/admin/system/database-queries")}

      not socket.assigns.pending_delete? ->
        {:noreply, socket}

      true ->
        query = socket.assigns.query
        socket = assign(socket, :pending_delete?, false)

        case User.delete_database_query(scope, user_id, query.id) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> put_flash(:success, "Query “#{query.name}” was deleted.")
             |> push_navigate(to: ~p"/admin/system/database-queries")}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "That query no longer exists.")
             |> push_navigate(to: ~p"/admin/system/database-queries")}

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

  # #650: the whole console is operator-only. Mount gates it, and every write and
  # execution repeats the operator proof captured in that mount's scope. A changed
  # tenant marker is observed by a fresh authenticated mount.
  defp operator?(socket) do
    case socket.assigns.current_scope do
      %{scope: %Scope{} = scope} -> Scope.platform_operator?(scope)
      _ -> false
    end
  end

  defp loaded_query?(socket, slug) do
    match?(%{slug: ^slug}, socket.assigns.query)
  end

  defp persist_result_nav?(socket) do
    not socket.assigns.is_new and match?(%{slug: slug} when is_binary(slug), socket.assigns.query)
  end

  # Page and page size come from the URL. Sort and unsaved SQL stay on the
  # process, because this patch is only the pager moving.
  defp navigate_results(socket, params) do
    page_size = result_page_size(params["page_size"] || params["perPage"])

    socket
    |> assign(:result_page, result_page(params["page"]))
    |> assign(:result_per_page, page_size)
    |> assign(:results_filters_form, results_filters_form(page_size))
    |> execute_query()
    |> clamp_result_page()
  end

  # Run, sort, and the pager all land on a result page. A saved query moves
  # there through the URL, so a reload shows the page on screen.
  defp show_result_page(socket, page) do
    if persist_result_nav?(socket) do
      push_patch(socket, to: result_path(socket, page: page))
    else
      socket |> assign(:result_page, page) |> execute_query()
    end
  end

  # A URL page past the last result page, from a stale bookmark or a
  # statement that now returns fewer rows, patches to the last page.
  defp clamp_result_page(socket) do
    case socket.assigns.results do
      %{total_pages: last} when socket.assigns.result_page > last ->
        push_patch(socket, to: result_path(socket, page: last), replace: true)

      _ ->
        socket
    end
  end

  defp result_path(socket, opts) do
    page = Keyword.get(opts, :page, socket.assigns.result_page)
    page_size = Keyword.get(opts, :page_size, socket.assigns.result_per_page)

    ~p"/admin/system/database-queries/#{socket.assigns.query.slug}?#{%{page: page, page_size: page_size}}"
  end

  defp results_filters_form(page_size) do
    to_form(%{"perPage" => Integer.to_string(page_size)}, as: :results)
  end

  defp results_page(results) do
    %{
      page: results.page,
      page_size: results.per_page,
      total_entries: results.total,
      total_pages: if(results.total == 0, do: 0, else: results.total_pages)
    }
  end

  defp result_page(value), do: max(to_integer(value, 1), 1)

  defp result_page_size(value) do
    parsed = to_integer(value, @default_page_size)
    if parsed in @page_sizes, do: parsed, else: @default_page_size
  end

  defp execute_query(socket) do
    sql = socket.assigns.sql_query
    params = socket.assigns.param_values
    page = socket.assigns.result_page
    per_page = socket.assigns.result_per_page
    sort_by = socket.assigns.result_sort_by
    sort_dir = socket.assigns.result_sort_dir

    opts = [
      page: page,
      per_page: per_page,
      sort_by: sort_by,
      sort_dir: sort_dir,
      # #650: pass the mount-proven operator marker at the engine boundary. The
      # executor fails closed without it; this guard does not re-resolve tenancy.
      operator: operator?(socket),
      # Recorded with the command. This page keeps no recorder of its own:
      # the executor records every command it is handed, whatever the
      # outcome, with the actor and client the web edge put in the audit
      # context at mount. A handler added here cannot run SQL unrecorded.
      name: socket.assigns.name
    ]

    case Database.execute_readonly(sql, params, opts) do
      {:ok, results} ->
        socket |> assign(:results, results) |> assign(:error, nil)

      {:error, reason} ->
        socket |> assign(:results, nil) |> assign(:error, format_db_error(reason))
    end
  end

  defp format_db_error(%{message: msg}), do: msg
  defp format_db_error(msg) when is_binary(msg), do: msg
  defp format_db_error(term), do: inspect(term)

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
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
