defmodule Bilimbi.Core.User.Web.NotificationBellComponent do
  @moduledoc """
  Top-bar notification bell LiveComponent.
  Displays an unread badge and dropdown list of recent notifications
  for the signed-in user within tenant scope.

  The panel follows the contract the shell's own disclosures (account,
  timezone) keep: opening moves focus to its first control, Escape closes it
  and returns focus to the bell, and a click outside closes it. The Escape
  listener is the panel's own, so a closed bell never claims the key.
  """

  use Bilimbi.Base.UI, :live_component

  # Self-service: `mark_all_read` acts on the signed-in actor's own
  # notifications, resolved from the session scope. `toggle_dropdown` only
  # flips the open/closed assign (#420).
  @write_guard_opt_out ~w(mark_all_read toggle_dropdown)

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
    scope = current_scope.scope
    {unread_count, items} = load_data(scope)

    socket =
      socket
      |> assign(assigns)
      |> assign(:unread_count, unread_count)
      |> assign(:items, items)

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    current_scope = socket.assigns[:current_scope]
    scope = current_scope && current_scope.scope

    if scope do
      {unread_count, items} = load_data(scope)

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
        {unread_count, items} = load_data(scope)

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

    if scope do
      User.mark_all_notifications_as_read(scope)
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

    notification =
      Enum.find(socket.assigns.items, fn item -> item.id == id end)

    url = if notification, do: Notification.url(notification), else: nil

    if scope do
      User.mark_notification_as_read(scope, id)
    end

    unread_count =
      case User.unread_notification_count(scope) do
        {:ok, count} -> count
        _ -> 0
      end

    recent =
      case User.list_notifications(scope, limit: @recent_limit) do
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

  defp load_data(scope) do
    if scope do
      unread =
        case User.unread_notification_count(scope) do
          {:ok, count} -> count
          _ -> 0
        end

      recent =
        case User.list_notifications(scope, limit: @recent_limit) do
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
