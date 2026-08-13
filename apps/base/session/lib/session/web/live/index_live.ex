defmodule Bilimbi.Base.Session.Web.IndexLive do
  @moduledoc """
  Operational session list.

  User identity is shown as `Guest` or `User \#{id}` from the durable row.
  This screen does not join Core User.
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
    @manage_cap in socket.assigns.current_scope.capabilities
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
    |> stream(:sessions, rows, reset: true)
  end

  defp search_query(%{"q" => q}) when is_binary(q), do: String.trim(q)
  defp search_query(_params), do: ""

  defp user_label(%{user_id: nil}), do: "Guest"
  defp user_label(%{user_id: id}), do: "User #{id}"

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
      delta < 3_600 -> "#{div(delta, 60)} minutes ago"
      delta < 86_400 -> "#{div(delta, 3_600)} hours ago"
      true -> "#{div(delta, 86_400)} days ago"
    end
  end
end
