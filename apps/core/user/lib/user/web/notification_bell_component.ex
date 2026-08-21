defmodule Bilimbi.Core.User.Web.NotificationBellComponent do
  @moduledoc """
  Top-bar notification bell LiveComponent.
  Displays an unread badge and dropdown list of recent notifications
  for the signed-in user within tenant scope.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Notification
  alias Phoenix.LiveView.JS

  @recent_limit 5

  @impl true
  def mount(socket) do
    {:ok, assign(socket, open: false, items: [], unread_count: 0)}
  end

  @impl true
  def update(%{current_scope: current_scope} = assigns, socket) do
    user_id = current_user_id(current_scope)
    scope = current_scope.scope

    {unread_count, items} = load_data(scope, user_id)

    socket =
      socket
      |> assign(assigns)
      |> assign(:user_id, user_id)
      |> assign(:unread_count, unread_count)
      |> assign(:items, items)

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    current_scope = socket.assigns[:current_scope]
    user_id = socket.assigns[:user_id] || (current_scope && current_user_id(current_scope))
    scope = current_scope && current_scope.scope

    if scope && user_id && user_id > 0 do
      {unread_count, items} = load_data(scope, user_id)

      {:ok,
       socket
       |> assign(:unread_count, unread_count)
       |> assign(:items, items)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("toggle_dropdown", _params, socket) do
    open? = not socket.assigns.open

    socket =
      if open? do
        scope = socket.assigns.current_scope.scope
        user_id = socket.assigns.user_id
        {unread_count, items} = load_data(scope, user_id)

        socket
        |> assign(:open, true)
        |> assign(:unread_count, unread_count)
        |> assign(:items, items)
      else
        assign(socket, :open, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    scope = socket.assigns.current_scope.scope
    user_id = socket.assigns.user_id

    if scope && user_id > 0 do
      User.mark_all_notifications_as_read(scope, user_id)
    end

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    items =
      Enum.map(socket.assigns.items, fn item ->
        %{item | read_at: item.read_at || now}
      end)

    {:noreply,
     socket
     |> assign(:unread_count, 0)
     |> assign(:items, items)}
  end

  @impl true
  def handle_event("visit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope.scope
    user_id = socket.assigns.user_id

    notification =
      Enum.find(socket.assigns.items, fn item -> item.id == id end)

    url = if notification, do: Notification.url(notification), else: nil

    if scope && user_id > 0 do
      User.mark_notification_as_read(scope, user_id, id)
    end

    unread_count =
      case User.unread_notification_count(scope, user_id) do
        {:ok, count} -> count
        _ -> 0
      end

    recent =
      case User.list_notifications(scope, user_id, limit: @recent_limit) do
        {:ok, list} -> list
        _ -> []
      end

    socket =
      socket
      |> assign(:open, false)
      |> assign(:unread_count, unread_count)
      |> assign(:items, recent)

    if url do
      {:noreply, push_navigate(socket, to: url)}
    else
      {:noreply, socket}
    end
  end

  defp load_data(scope, user_id) do
    if user_id > 0 and scope do
      unread =
        case User.unread_notification_count(scope, user_id) do
          {:ok, count} -> count
          _ -> 0
        end

      recent =
        case User.list_notifications(scope, user_id, limit: @recent_limit) do
          {:ok, list} -> list
          _ -> []
        end

      {unread, recent}
    else
      {0, []}
    end
  end

  def badge_count(count) when count > 99, do: "99+"
  def badge_count(count), do: to_string(count)

  def aria_label(0), do: "Notifications"
  def aria_label(1), do: "1 unread notification"
  def aria_label(count), do: "#{badge_count(count)} unread notifications"
end
