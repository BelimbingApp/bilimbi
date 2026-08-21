defmodule Bilimbi.Core.User.Web.DatabaseQueriesLive.Show do
  @moduledoc """
  Show and edit page for a single database query.

  Ports Belimbing's `app/Base/Database/Livewire/Queries/Show.php`.
  Supports natural language prompt, SQL editing, dynamic named parameter inputs,
  read-only query execution, pagination, sorting, and user-scoped query management.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Database
  alias Bilimbi.Core.User

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
     |> assign(:is_new, false)
     |> assign(:query, nil)
     |> assign(:name, "Untitled Query")
     |> assign(:description, "")
     |> assign(:prompt, "")
     |> assign(:sql_query, "")
     |> assign(:detected_params, [])
     |> assign(:param_values, %{})
     |> assign(:error, nil)
     |> assign(:results, nil)
     |> assign(:result_page, 1)
     |> assign(:result_per_page, 25)
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
  def handle_params(%{"slug" => slug}, _uri, socket) do
    scope = socket.assigns.current_scope.scope
    user_id = current_user_id(socket.assigns.current_scope)

    case User.get_database_query(scope, user_id, slug) do
      {:ok, query} ->
        sql = query.sql_query || ""
        detected = Database.extract_named_parameters(sql)
        default_params = Map.new(detected, fn p -> {p, ""} end)

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

        # Automatically execute query if SQL is non-empty
        {:noreply, if(String.trim(sql) != "", do: execute_query(socket), else: socket)}

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
    if allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
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
             |> put_flash(:info, "Query saved.")
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
             |> put_flash(:info, "Query saved.")}

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
      {:noreply,
       socket
       |> assign(:result_page, 1)
       |> execute_query()}
    end
  end

  @impl true
  def handle_event("sort_results", %{"column" => column}, socket) do
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
     |> assign(:result_page, 1)
     |> execute_query()}
  end

  @impl true
  def handle_event("page_results", %{"page" => page}, socket) do
    page_num = to_integer(page, 1)

    {:noreply,
     socket
     |> assign(:result_page, page_num)
     |> execute_query()}
  end

  @impl true
  def handle_event("duplicate", _params, socket) do
    if allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)

      if socket.assigns.query do
        case User.duplicate_database_query(scope, user_id, socket.assigns.query.id) do
          {:ok, duplicate} ->
            {:noreply,
             socket
             |> put_flash(:info, "Query duplicated.")
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
  def handle_event("delete", _params, socket) do
    if allowed?(socket.assigns.current_scope, "admin.system.database-table.edit") do
      scope = socket.assigns.current_scope.scope
      user_id = current_user_id(socket.assigns.current_scope)

      if socket.assigns.is_new || is_nil(socket.assigns.query) do
        {:noreply,
         socket
         |> put_flash(:info, "Query discarded.")
         |> push_navigate(to: ~p"/admin/system/database-queries")}
      else
        case User.delete_database_query(scope, user_id, socket.assigns.query.id) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> put_flash(:info, "Query deleted.")
             |> push_navigate(to: ~p"/admin/system/database-queries")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not delete query.")}
        end
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to modify queries.")}
    end
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
      sort_dir: sort_dir
    ]

    case Database.execute_readonly(sql, params, opts) do
      {:ok, results} ->
        maybe_record_audit(socket, sql)
        socket |> assign(:results, results) |> assign(:error, nil)

      {:error, reason} ->
        socket |> assign(:results, nil) |> assign(:error, format_db_error(reason))
    end
  end

  defp maybe_record_audit(socket, sql) do
    if Map.has_key?(socket.assigns, :current_scope) and
         Map.has_key?(socket.assigns.current_scope, :scope) and
         Map.has_key?(socket.assigns.current_scope, :actor) do
      scope = socket.assigns.current_scope.scope
      actor = socket.assigns.current_scope.actor

      audit_attrs = %{
        actor_type: to_string(actor.type),
        actor_id: actor.id,
        company_id: actor.company_id,
        event: "database_query.executed",
        payload: %{"name" => socket.assigns.name, "sql" => sql},
        is_retained: false,
        occurred_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }

      Bilimbi.Base.Audit.record_action(scope, audit_attrs)
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
