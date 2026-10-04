defmodule BilimbiWeb.UserNotificationsLiveTest do
  @moduledoc """
  Tests for the `/notifications` index LiveView and the top-bar notification bell component.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Ecto.Adapters.SQL

  setup do
    UserFixtures.create_user_tables!()
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

  defp subscriptions(view) do
    BilimbiWeb.PubSub
    |> Registry.lookup(User.notification_topic(41, 91))
    |> Enum.count(fn {pid, _meta} -> pid == view.pid end)
  end

  for action <- [:patch, :toggle_dropdown, :mark_all_read, :visit, :broadcast, :component_update] do
    @expiry_action action
    test "expired sessions reject #{@expiry_action}", %{conn: conn, scope: scope} do
      {:ok, note} = User.send_notification(scope, 91, %{title: "Private update"})
      conn = log_in_as(conn)
      session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
      {:ok, view, _html} = live(conn, ~p"/notifications")
      render_click(element(view, "#app-notifications-bell"))
      {:ok, entry} = Session.fetch_session(session_id)

      {:ok, _entry} =
        Session.put_session(session_id, entry.payload, %{
          user_id: 91,
          last_activity: System.system_time(:second) - 120 * 60 - 1
        })

      case @expiry_action do
        :patch ->
          render_click(element(view, "#filter-unread-tab"))

        :toggle_dropdown ->
          render_click(element(view, "#app-notifications-bell"))

        :mark_all_read ->
          render_click(element(view, "#bell-mark-all-read"))

        :visit ->
          render_click(element(view, "#bell-item-#{note.id} button"))

        :broadcast ->
          send(view.pid, {:notification_event, :created})

        :component_update ->
          Phoenix.LiveView.send_update(view.pid, User.Web.NotificationBellComponent,
            id: "app-shell-notifications"
          )
      end

      assert_redirect(view, "/")
      assert {:ok, 1} = User.unread_notification_count(as(scope, 91))
    end
  end

  test "background notifications do not extend activity, but component events do", %{conn: conn} do
    conn = log_in_as(conn)
    session_id = Plug.Conn.get_session(conn, "current_user")["session_id"]
    {:ok, view, _html} = live(conn, ~p"/notifications")
    {:ok, entry} = Session.fetch_session(session_id)
    activity = System.system_time(:second) - 10 * 60

    {:ok, _entry} =
      Session.put_session(session_id, entry.payload, %{user_id: 91, last_activity: activity})

    send(view.pid, {:notification_event, :created})
    assert has_element?(view, "#app-notifications-bell")
    assert {:ok, %{last_activity: ^activity}} = Session.fetch_session(session_id)

    render_click(element(view, "#app-notifications-bell"))
    assert has_element?(view, "#app-notifications-dropdown")
    assert {:ok, %{last_activity: refreshed}} = Session.fetch_session(session_id)
    assert refreshed > activity
  end

  for framed? <- [true, false] do
    @framed framed?
    test "notification actions preserve framed=#{@framed} rendering", %{conn: conn, scope: scope} do
      {:ok, _note} = User.send_notification(scope, 91, %{title: "Workspace update"})
      conn = log_in_as(conn)
      conn = if @framed, do: put_req_header(conn, "sec-fetch-dest", "iframe"), else: conn
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#app-shell[data-framed='true']") == @framed
      render_click(element(view, "#mark-all-read-btn"))
      assert {:ok, 0} = User.unread_notification_count(as(scope, 91))
      assert has_element?(view, "#app-shell[data-framed='true']") == @framed
      assert has_element?(view, "#app-topbar") == not @framed

      render_click(element(view, "#filter-read-tab"))
      assert has_element?(view, "#app-shell[data-framed='true']") == @framed
      assert has_element?(view, "#notifications-list")
    end
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/notifications")
  end

  test "renders empty state when there are no notifications", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#notifications-empty", "No notifications")
    # The label alone carries the empty state; no consumer-voice second line (#653).
    refute has_element?(view, "#notifications-empty", "all caught up")
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
    assert has_element?(view, "#notifications-list [id$='#{n1.id}']", "Welcome aboard")

    assert has_element?(
             view,
             "#notifications-list [id$='#{n1.id}']",
             "Your profile has been created."
           )
  end

  test "renders each notification's created time through the shared datetime", %{
    conn: conn,
    scope: scope
  } do
    {:ok, note} = User.send_notification(scope, 91, %{title: "Clocked update"})
    created_at = ~N[2026-08-18 10:00:00]

    SQL.query!(Repo, "UPDATE notifications SET created_at = $1 WHERE id = $2", [
      created_at,
      Ecto.UUID.dump!(note.id)
    ])

    :ok =
      Settings.put("localization.timezone", "Asia/Kuala_Lumpur", SettingsScope.company(73, 41))
      |> case do
        {:ok, _value} -> :ok
        other -> other
      end

    {:ok, :company} = DateTimePolicy.put_mode(SettingsScope.user(91, 73, 41), "company")

    {:ok, view, _html} = open(conn)

    assert has_element?(
             view,
             ~s(time#notification-created-#{note.id}[datetime="2026-08-18T10:00:00Z"][data-follow-shell="true"][phx-hook="DateTime"][data-text-company="18/08/2026, 18:00 +08"][data-text-utc="18/08/2026, 10:00 UTC"]),
             "18/08/2026, 18:00 +08"
           )

    refute has_element?(view, "#notification-created-#{note.id}", "ago")
    refute has_element?(view, "#notification-created-#{note.id}", "Just now")
  end

  test "renders a row whose stored icon name is a legacy Belimbing one", %{
    conn: conn,
    scope: scope
  } do
    {:ok, legacy} =
      User.send_notification(scope, 91, %{
        title: "Adopted from Belimbing",
        icon: "heroicon-o-bell"
      })

    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#notifications-list [id$='#{legacy.id}']")

    assert has_element?(
             view,
             "#notifications-list [id$='#{legacy.id}']",
             "Adopted from Belimbing"
           )
  end

  test "filters by all, unread, and read tabs", %{conn: conn, scope: scope} do
    {:ok, n1} = User.send_notification(scope, 91, %{title: "Note 1 Unread"})
    {:ok, n2} = User.send_notification(scope, 91, %{title: "Note 2 Read"})
    User.mark_notification_as_read(as(scope, 91), n2.id)

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
    assert User.unread_notification_count(as(scope, 91)) == {:ok, 0}
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
    assert User.unread_notification_count(as(scope, 91)) == {:ok, 0}
  end

  test "marks all notifications as read", %{conn: conn, scope: scope} do
    {:ok, _n1} = User.send_notification(scope, 91, %{title: "Note 1"})
    {:ok, _n2} = User.send_notification(scope, 91, %{title: "Note 2"})

    {:ok, view, _html} = open(conn)
    assert has_element?(view, "#mark-all-read-btn")

    view |> element("#mark-all-read-btn") |> render_click()

    assert User.unread_notification_count(as(scope, 91)) == {:ok, 0}
    refute has_element?(view, "#mark-all-read-btn")
    assert has_element?(view, "#flash-success", "All notifications marked as read.")
  end

  test "supports pagination and per_page controls", %{conn: conn, scope: scope} do
    for i <- 1..30 do
      User.send_notification(scope, 91, %{title: "Pagination Note #{i}"})
    end

    {:ok, view, _html} = open(conn)

    # The standard <.pagination> ids and summary (#653).
    assert has_element?(view, "#notifications-pagination")

    assert has_element?(
             view,
             "#notifications-pagination-summary",
             "Showing 1 to 25 of 30 results"
           )

    assert has_element?(view, "#notifications-pagination-page-size")
    assert has_element?(view, "#notifications-pagination-previous[disabled]")

    # Navigate to page 2
    view |> element("#notifications-pagination-next") |> render_click()

    assert has_element?(
             view,
             "#notifications-pagination-summary",
             "Showing 26 to 30 of 30 results"
           )

    assert has_element?(view, "#notifications-pagination-next[disabled]")
    refute has_element?(view, "#notifications-pagination-previous[disabled]")

    # The size select feeds the standard filters event and patches per_page.
    view
    |> form("#notifications-pagination-page-size-form", %{"filters" => %{"perPage" => "50"}})
    |> render_change()

    assert has_element?(
             view,
             "#notifications-pagination-summary",
             "Showing 1 to 30 of 30 results"
           )
  end

  test "does not show notifications belonging to other users", %{conn: conn, scope: scope} do
    {:ok, n_other} = User.send_notification(scope, 92, %{title: "Grace Secret Note"})

    {:ok, view, _html} = open(conn)
    refute has_element?(view, "#notifications-list [id$='#{n_other.id}']")
    refute has_element?(view, "#notifications-list", "Grace Secret Note")
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
      assert has_element?(view, "#app-notifications-unread-badge", "1")

      # Dropdown is closed initially
      refute has_element?(view, "#app-notifications-dropdown")

      # Toggle dropdown open
      view |> element("#app-notifications-bell") |> render_click()
      assert has_element?(view, "#app-notifications-dropdown")
      assert has_element?(view, "#bell-item-#{n1.id}")
      assert has_element?(view, "#bell-item-#{n1.id}", "Alert for Bell")

      # The open panel follows the shell's disclosure contract: focus moves
      # into it on open, Escape closes it and returns focus to the bell. The
      # listener is the panel's own, so a closed bell claims no key.
      assert has_element?(view, "#app-notifications-dropdown[phx-mounted][phx-key='escape']")
      refute has_element?(view, "#app-shell-notifications[phx-window-keydown]")

      for fragment <- ["close_dropdown", "focus", "#app-notifications-bell"] do
        assert has_element?(
                 view,
                 "#app-notifications-dropdown[phx-window-keydown*='#{fragment}']"
               )
      end

      view |> element("#app-notifications-dropdown") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#app-notifications-dropdown")
      assert has_element?(view, "#app-notifications-bell[aria-expanded='false']")

      view |> element("#app-notifications-bell") |> render_click()
      assert has_element?(view, "#app-notifications-dropdown")

      # Mark all as read from dropdown
      view |> element("#bell-mark-all-read") |> render_click()
      assert User.unread_notification_count(as(scope, 91)) == {:ok, 0}
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
      assert has_element?(view, "#app-notifications-unread-badge")
      assert has_element?(view, "#app-notifications-unread-badge", "1")
    end

    # The bell belongs to the shared shell, so a module page that never names
    # it has it, and the subscription reaches it there.
    for path <- ["/settings/profile", "/settings/appearance", "/notifications"] do
      @path path
      test "the shell renders a live bell on #{@path}", %{conn: conn, scope: scope} do
        {:ok, view, _html} = conn |> log_in_as() |> live(@path)

        assert has_element?(view, "#app-topbar #app-shell-notifications #app-notifications-bell")
        refute has_element?(view, "#app-notifications-unread-badge")

        {:ok, _note} = User.send_notification(scope, 91, %{title: "Shell alert"})

        # The hook answers the event with a `send_update` the LiveView sends
        # itself; one render lets it handle that message first.
        _ = render(view)
        assert has_element?(view, "#app-notifications-unread-badge", "1")
      end
    end

    test "a page with no clause for the event survives a notification", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/settings/profile")
      ref = Process.monitor(view.pid)

      {:ok, _note} = User.send_notification(scope, 91, %{title: "Shell alert"})

      _ = render(view)
      assert has_element?(view, "#app-notifications-unread-badge")
      refute_received {:DOWN, ^ref, :process, _pid, _reason}
    end

    test "a framed page has no bell and holds no subscription", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> put_req_header("sec-fetch-dest", "iframe")
        |> live(~p"/settings/profile")

      refute has_element?(view, "#app-notifications-bell")
      assert subscriptions(view) == 0
    end

    test "the framed notifications list still follows new notifications", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} =
        conn
        |> log_in_as()
        |> put_req_header("sec-fetch-dest", "iframe")
        |> live(~p"/notifications")

      refute has_element?(view, "#app-notifications-bell")
      assert subscriptions(view) == 1

      {:ok, note} = User.send_notification(scope, 91, %{title: "Framed alert"})

      assert has_element?(view, "#notifications-list [id$='#{note.id}']")
    end

    # The regression #424 fixed: NotificationsLive subscribed in its own `mount/3`
    # while the session's `on_mount` hook (now `NotificationSubscription`) had
    # already subscribed the same process to the same topic, so every event was
    # delivered twice.
    #
    # Asserted against the registry rather than by counting messages, because a
    # duplicate registration is the defect itself — counting deliveries would make
    # this a timing test, and a second subscriber would still be there when it
    # happened to pass.
    test "the LiveView process is registered on its notification topic exactly once",
         %{conn: conn} do
      {:ok, view, _html} = open(conn)

      topic = User.notification_topic(41, 91)

      own_registrations =
        BilimbiWeb.PubSub
        |> Registry.lookup(topic)
        |> Enum.filter(fn {pid, _meta} -> pid == view.pid end)

      assert length(own_registrations) == 1,
             """
             Expected the notifications LiveView to hold exactly one subscription
             to #{topic}, found #{length(own_registrations)}.

             More than one means something subscribed in `mount/3` on top of
             `NotificationSubscription.on_mount/4`, and every notification
             will be delivered once per registration.
             """
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
      assert has_element?(view, "#notifications-list [id$='#{note.id}']", "Realtime PubSub Alert")
      refute has_element?(view, "#notifications-empty")
      refute has_element?(view, "#flash-error")
    end

    test "logs a warning when the notification subscription fails", %{conn: conn} do
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

        assert log =~ "failed to subscribe to the notifications topic for user 91"
      after
        Application.put_env(:bilimbi_core_user, :pubsub_server, orig)
      end
    end
  end

  defp as(scope, user_id) do
    Bilimbi.Base.Tenancy.Authentication.sign_in(scope, user_id, 73)
  end
end
