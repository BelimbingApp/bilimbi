defmodule BilimbiWeb.UserNotificationsLiveTest do
  @moduledoc """
  Tests for the `/notifications` index LiveView and the top-bar notification bell component.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_notifications_table!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant 41"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Company 73"})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com",
      email_verified_at: ~N[2026-01-01 00:00:00]
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, scope: scope}
  end

  defp open(conn), do: conn |> log_in_as() |> live(~p"/notifications")

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/notifications")
  end

  test "renders empty state when there are no notifications", %{conn: conn} do
    {:ok, view, html} = open(conn)

    assert has_element?(view, "#notifications-empty")
    assert html =~ "No notifications"
    assert html =~ "You&#39;re all caught up."
  end

  test "renders notification items with title, body, and unread indicator", %{
    conn: conn,
    scope: scope
  } do
    {:ok, n1} =
      User.send_notification(scope, 91, %{
        title: "Welcome aboard",
        body: "Your profile has been created.",
        url: "/settings/profile"
      })

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#notifications-list")
    assert has_element?(view, "#notifications-list [id$='#{n1.id}']")
    assert has_element?(view, "#mark-read-#{n1.id}")
    assert render(view) =~ "Welcome aboard"
    assert render(view) =~ "Your profile has been created."
  end

  test "filters by all, unread, and read tabs", %{conn: conn, scope: scope} do
    {:ok, n1} = User.send_notification(scope, 91, %{title: "Note 1 Unread"})
    {:ok, n2} = User.send_notification(scope, 91, %{title: "Note 2 Read"})
    User.mark_notification_as_read(scope, 91, n2.id)

    {:ok, view, _html} = open(conn)

    # In 'all' filter, both are visible
    assert has_element?(view, "#notifications-list [id$='#{n1.id}']")
    assert has_element?(view, "#notifications-list [id$='#{n2.id}']")

    # Switch to 'unread'
    view |> element("#filter-unread-tab") |> render_click()
    assert has_element?(view, "#notifications-list [id$='#{n1.id}']")
    refute has_element?(view, "#notifications-list [id$='#{n2.id}']")

    # Switch to 'read'
    view |> element("#filter-read-tab") |> render_click()
    refute has_element?(view, "#notifications-list [id$='#{n1.id}']")
    assert has_element?(view, "#notifications-list [id$='#{n2.id}']")
  end

  test "marks single notification as read", %{conn: conn, scope: scope} do
    {:ok, n1} = User.send_notification(scope, 91, %{title: "Needs Attention"})

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#mark-read-#{n1.id}")

    view |> element("#mark-read-#{n1.id}") |> render_click()

    refute has_element?(view, "#mark-read-#{n1.id}")
    assert User.unread_notification_count(scope, 91) == {:ok, 0}
  end

  test "in unread filter, marking last unread notification transitions to empty state", %{
    conn: conn,
    scope: scope
  } do
    {:ok, n1} = User.send_notification(scope, 91, %{title: "Last Unread Note"})

    {:ok, view, _html} =
      conn |> log_in_as() |> live(~p"/notifications?filter=unread")

    assert has_element?(view, "#notifications-list [id$='#{n1.id}']")
    refute has_element?(view, "#notifications-empty")

    view |> element("#mark-read-#{n1.id}") |> render_click()

    # Now empty state should immediately be displayed
    assert has_element?(view, "#notifications-empty")
    refute has_element?(view, "#notifications-list")
    assert User.unread_notification_count(scope, 91) == {:ok, 0}
  end

  test "marks all notifications as read", %{conn: conn, scope: scope} do
    {:ok, _n1} = User.send_notification(scope, 91, %{title: "Note 1"})
    {:ok, _n2} = User.send_notification(scope, 91, %{title: "Note 2"})

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#mark-all-read-btn")

    view |> element("#mark-all-read-btn") |> render_click()

    assert User.unread_notification_count(scope, 91) == {:ok, 0}
    refute has_element?(view, "#mark-all-read-btn")
    assert render(view) =~ "All notifications marked as read."
  end

  test "supports pagination and per_page controls", %{conn: conn, scope: scope} do
    for i <- 1..30 do
      User.send_notification(scope, 91, %{title: "Pagination Note #{i}"})
    end

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#notifications-pagination")
    assert has_element?(view, "#pagination-summary", "Showing 1 to 25 of 30 notifications")
    assert has_element?(view, "#pagination-next")
    assert has_element?(view, "#pagination-prev-disabled")

    # Navigate to page 2
    view |> element("#pagination-next") |> render_click()
    assert has_element?(view, "#pagination-summary", "Showing 26 to 30 of 30 notifications")
    assert has_element?(view, "#pagination-prev")
    assert has_element?(view, "#pagination-next-disabled")
  end

  test "does not show notifications belonging to other users", %{conn: conn, scope: scope} do
    {:ok, n_other} = User.send_notification(scope, 92, %{title: "Grace Secret Note"})

    {:ok, view, _html} = open(conn)
    refute has_element?(view, "#notifications-list [id$='#{n_other.id}']")
    refute render(view) =~ "Grace Secret Note"
  end

  describe "top-bar NotificationBellComponent" do
    test "renders bell with unread badge, dropdown, and mark all as read action", %{
      conn: conn,
      scope: scope
    } do
      {:ok, n1} =
        User.send_notification(scope, 91, %{title: "Alert for Bell", body: "Important details"})

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/dashboard")

      # Bell button exists with badge
      assert has_element?(view, "#app-notifications-bell")
      assert has_element?(view, "#app-notifications-unread-badge")
      assert element(view, "#app-notifications-unread-badge") |> render() =~ "1"

      # Dropdown is closed initially
      refute has_element?(view, "#app-notifications-dropdown")

      # Toggle dropdown open
      view |> element("#app-notifications-bell") |> render_click()
      assert has_element?(view, "#app-notifications-dropdown")
      assert has_element?(view, "#bell-item-#{n1.id}")
      assert render(view) =~ "Alert for Bell"

      # Mark all as read from dropdown
      view |> element("#bell-mark-all-read") |> render_click()
      assert User.unread_notification_count(scope, 91) == {:ok, 0}
      refute has_element?(view, "#app-notifications-unread-badge")
    end

    test "caps dropdown items at 5 recent notifications", %{conn: conn, scope: scope} do
      for i <- 1..8 do
        User.send_notification(scope, 91, %{title: "Note #{i}"})
      end

      {:ok, view, _html} =
        conn |> log_in_as() |> live(~p"/dashboard")

      view |> element("#app-notifications-bell") |> render_click()
      assert has_element?(view, "#app-notifications-dropdown")

      # Dropdown must contain at most 5 notification items
      assert length(
               element(view, "#app-notifications-dropdown")
               |> render()
               |> String.split("bell-item-")
             ) - 1 == 5
    end

    test "live PubSub update refreshes bell unread badge while /dashboard is mounted", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

      # Initially no unread badge
      refute has_element?(view, "#app-notifications-unread-badge")

      # Deliver a new notification via Core User domain API while dashboard is mounted
      {:ok, _note} = User.send_notification(scope, 91, %{title: "Mounted Dashboard Alert"})

      # The LiveView hook receives the event and updates the bell component live
      _ = render(view)
      assert render(view) =~ "app-notifications-unread-badge"
      assert has_element?(view, "#app-notifications-unread-badge")
      assert element(view, "#app-notifications-unread-badge") |> render() =~ "1"
    end

    test "mounts through UserAuth without false error flash and receives real-time updates",
         %{
           conn: conn,
           scope: scope
         } do
      {:ok, view, _html} = open(conn)

      refute has_element?(view, "#flash-error")
      assert has_element?(view, "#notifications-empty")

      # Send a new notification to the signed-in user while view is connected
      {:ok, note} = User.send_notification(scope, 91, %{title: "Realtime PubSub Alert"})

      # The LiveView receives the PubSub broadcast and updates its assigns/stream
      assert has_element?(view, "#notifications-list [id$='#{note.id}']")
      assert render(view) =~ "Realtime PubSub Alert"
      refute has_element?(view, "#notifications-empty")
      refute has_element?(view, "#flash-error")
    end

    test "logs warning when notification subscription fails in UserAuth", %{conn: conn} do
      name = :failing_pubsub_test
      start_supervised!({Registry, keys: :unique, name: name})
      Registry.register(name, "user_notifications:41:91", nil)

      orig = Application.get_env(:bilimbi_core_user, :pubsub_server)

      try do
        Application.put_env(:bilimbi_core_user, :pubsub_server, name)

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            {:ok, _view, _html} = open(conn)
          end)

        assert log =~ "UserAuth: failed to subscribe to user notifications topic"
      after
        Application.put_env(:bilimbi_core_user, :pubsub_server, orig)
      end
    end
  end
end
