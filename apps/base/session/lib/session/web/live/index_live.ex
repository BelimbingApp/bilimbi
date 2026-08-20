defmodule Bilimbi.Base.Session.Web.IndexLive do
  @moduledoc """
  Operational session list.

  Names the signed-in user where it can. A session row carries only `user_id`,
  and Belimbing's screen left-joins `users` to show `user_name`
  (`resources/core/views/livewire/admin/system/sessions/index.blade.php:55`).

  Base cannot query Core, so the name is resolved through
  `Core.User.get_tenant_users/2` reached by reflection — the same idiom
  `core/company/web/show_live.ex` uses. `base/session` declares no dependency on
  `core/user` and this does not add one: if the module is absent, every row falls
  back to its id.

  What each row shows, per the ruling on #285:

  - `user_id` is nil → `Guest`, matching Belimbing's `?? __('Guest')`
  - the user is in the actor's tenant → **their name**
  - the user is outside it → `User \#{id}`

  The last case is why this is not a plain join: `get_tenant_users/2` is
  tenant-scoped by construction, so a session belonging to another tenant
  resolves to nothing and keeps its id rather than leaking a name across the
  tenant boundary.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Session

  @list_limit 25
  @manage_cap "admin.system.session.manage"

  @impl true
  def mount(_params, session, socket) do
    %{"current_user" => %{"session_id" => current_session_id}} = session

    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> assign(:current_session_id, current_session_id)
     |> assign(:query, "")
     |> refresh_sessions()}
  end

  @impl true
  def handle_event("search", params, socket) do
    query = search_query(params)

    {:noreply,
     socket
     |> assign(:query, query)
     |> refresh_sessions()}
  end

  def handle_event("terminate", %{"id" => id}, socket) do
    if can_manage?(socket) do
      terminate_listed(socket, id)
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to terminate sessions.")}
    end
  end

  defp terminate_listed(socket, id) do
    case Session.terminate_session(id, socket.assigns.current_session_id) do
      {:ok, :terminated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session terminated.")
         |> refresh_sessions()}

      {:ok, :not_found} ->
        {:noreply, refresh_sessions(socket)}

      {:error, :current_session} ->
        {:noreply, put_flash(socket, :error, "You cannot terminate your current session.")}
    end
  end

  defp can_manage?(socket) do
    allowed?(socket.assigns.current_scope, @manage_cap)
  end

  defp refresh_sessions(socket) do
    search =
      case socket.assigns.query do
        "" -> nil
        query -> query
      end

    rows = Session.list_sessions(search: search, limit: @list_limit)

    socket
    |> assign(:sessions_count, length(rows))
    |> assign(:user_names, user_names(socket, rows))
    |> stream(:sessions, rows, reset: true)
  end

  # Reflection rather than a declared dependency: `base/session` lists only
  # base/database, base/module_registry and base/ui, and naming a column is not
  # worth a module-graph edge. Absent Core User, every row keeps its id.
  defp user_names(socket, rows) do
    user_mod = Bilimbi.Core.User

    user_ids =
      rows
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if user_ids != [] and Code.ensure_loaded?(user_mod) and
         function_exported?(user_mod, :get_tenant_users, 2) do
      case apply(user_mod, :get_tenant_users, [socket.assigns.current_scope.scope, user_ids]) do
        {:ok, names} -> names
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp search_query(%{"q" => q}) when is_binary(q), do: String.trim(q)
  defp search_query(_params), do: ""

  defp user_label(%{user_id: nil}, _names), do: "Guest"

  defp user_label(%{user_id: id}, names) do
    case Map.get(names, id) do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> "User #{id}"
    end
  end

  defp truncate_ua(nil), do: "—"

  defp truncate_ua(user_agent) when is_binary(user_agent) do
    if String.length(user_agent) > 80 do
      String.slice(user_agent, 0, 80) <> "..."
    else
      user_agent
    end
  end

  defp relative_activity(unix) when is_integer(unix) do
    delta = max(System.system_time(:second) - unix, 0)

    cond do
      delta < 60 -> "just now"
      delta < 3_600 -> ago(div(delta, 60), "minute")
      delta < 86_400 -> ago(div(delta, 3_600), "hour")
      true -> ago(div(delta, 86_400), "day")
    end
  end

  # Belimbing renders this column through Carbon's `diffForHumans()`
  # (`resources/core/views/livewire/admin/system/sessions/index.blade.php:58`),
  # which pluralises per unit. Interpolating a hard-coded "s" meant every
  # session last seen between 24 and 48 hours ago read "1 days ago" -- a full
  # day wide, not an edge case.
  defp ago(1, unit), do: "1 #{unit} ago"
  defp ago(count, unit), do: "#{count} #{unit}s ago"
end
