defmodule Bilimbi.Core.User.Web.NotificationsLive do
  @moduledoc """
  User notifications index LiveView (`/notifications`).

  Displays paginated notifications for the signed-in user within tenant scope
  with filter tabs (All, Unread, Read), mark as read actions, and deep link navigation.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Notification

  @allowed_per_page [25, 50, 100, 300]
  @default_per_page 25

  @impl true
  def mount(_params, _session, socket) do
    user_id = current_user_id(socket.assigns.current_scope)
    scope = socket.assigns.current_scope.scope

    unread_count =
      case User.unread_notification_count(scope, user_id) do
        {:ok, count} -> count
        _ -> 0
      end

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:active_nav, nil)
     |> assign(:current_filter, :all)
     |> assign(:page, 1)
     |> assign(:per_page, @default_per_page)
     |> assign(:total_count, 0)
     |> assign(:total_pages, 1)
     |> assign(:notification_count, 0)
     |> assign(:user_id, user_id)
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = parse_filter(params["filter"])
    page = parse_pos_integer(params["page"], 1)
    per_page = parse_per_page(params["per_page"], @default_per_page)

    {:noreply,
     socket
     |> assign(:current_filter, filter)
     |> assign(:page, page)
     |> assign(:per_page, per_page)
     |> load_notifications(filter, page, per_page, reset: true)}
  end

  @impl true
  def handle_info({:notification_event, _event}, socket) do
    send_update(Bilimbi.Core.User.Web.NotificationBellComponent,
      id: "topbar-notification-bell",
      refresh: true
    )

    {:noreply,
     load_notifications(
       socket,
       socket.assigns.current_filter,
       socket.assigns.page,
       socket.assigns.per_page,
       reset: true
     )}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    user_id = socket.assigns.user_id
    scope = socket.assigns.current_scope.scope

    case User.mark_notification_as_read(scope, user_id, id) do
      {:ok, notification} ->
        if socket.assigns.current_filter == :unread do
          # Reload unread filter to accurately update count, pagination, and empty transitions
          {:noreply,
           load_notifications(
             socket,
             :unread,
             socket.assigns.page,
             socket.assigns.per_page,
             reset: true
           )}
        else
          unread_count =
            case User.unread_notification_count(scope, user_id) do
              {:ok, c} -> c
              _ -> 0
            end

          {:noreply,
           socket
           |> assign(:unread_count, unread_count)
           |> stream_insert(:notifications, notification)}
        end

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    user_id = socket.assigns.user_id
    scope = socket.assigns.current_scope.scope

    User.mark_all_notifications_as_read(scope, user_id)

    {:noreply,
     socket
     |> assign(:unread_count, 0)
     |> load_notifications(
       socket.assigns.current_filter,
       socket.assigns.page,
       socket.assigns.per_page,
       reset: true
     )
     |> put_flash(:info, "All notifications marked as read.")}
  end

  @impl true
  def handle_event("visit", %{"id" => id}, socket) do
    user_id = socket.assigns.user_id
    scope = socket.assigns.current_scope.scope

    case User.mark_notification_as_read(scope, user_id, id) do
      {:ok, notification} ->
        url = Notification.url(notification)

        if url do
          {:noreply, push_navigate(socket, to: url)}
        else
          unread_count =
            case User.unread_notification_count(scope, user_id) do
              {:ok, c} -> c
              _ -> 0
            end

          socket =
            socket
            |> assign(:unread_count, unread_count)
            |> stream_insert(:notifications, notification)

          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp load_notifications(socket, filter, page, per_page, opts) do
    user_id = socket.assigns.user_id
    scope = socket.assigns.current_scope.scope

    total_count =
      case User.count_notifications(scope, user_id, status: filter) do
        {:ok, count} -> count
        _ -> 0
      end

    unread_count =
      case User.unread_notification_count(scope, user_id) do
        {:ok, count} -> count
        _ -> 0
      end

    notifications =
      case User.list_notifications(scope, user_id,
             status: filter,
             page: page,
             per_page: per_page
           ) do
        {:ok, list} -> list
        _ -> []
      end

    total_pages = max(1, ceil(total_count / per_page))
    reset = Keyword.get(opts, :reset, false)

    socket
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:page, page)
    |> assign(:per_page, per_page)
    |> assign(:notification_count, total_count)
    |> assign(:unread_count, unread_count)
    |> stream(:notifications, notifications, reset: reset)
  end

  defp parse_filter("unread"), do: :unread
  defp parse_filter("read"), do: :read
  defp parse_filter(_), do: :all

  defp parse_pos_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_pos_integer(int, _default) when is_integer(int) and int > 0, do: int
  defp parse_pos_integer(_, default), do: default

  defp parse_per_page(val, default) do
    int = parse_pos_integer(val, default)
    if int in @allowed_per_page, do: int, else: default
  end

  def format_relative_time(nil), do: ""

  def format_relative_time(%NaiveDateTime{} = dt) do
    now = NaiveDateTime.utc_now()
    diff_seconds = NaiveDateTime.diff(now, dt)

    cond do
      diff_seconds < 60 ->
        "Just now"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes}m ago"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3600)
        "#{hours}h ago"

      diff_seconds < 604_800 ->
        days = div(diff_seconds, 86_400)
        "#{days}d ago"

      true ->
        Calendar.strftime(dt, "%b %d, %Y")
    end
  end
end
