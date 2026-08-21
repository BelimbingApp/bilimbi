defmodule Bilimbi.Core.User.UserNotificationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Notification
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @notification_delivery_failure_event [:bilimbi, :core, :user, :notification_delivery, :failed]

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_notifications_table!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant 41"})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Company 73",
      code: "company_73"
    })

    CompanyFixtures.insert_tenant!(%{id: 99, name: "Tenant 99"})

    CompanyFixtures.insert_company!(%{
      id: 88,
      tenant_id: 99,
      name: "Company 88",
      code: "company_88"
    })

    UserFixtures.insert_user!(%{
      id: 42,
      company_id: 73,
      name: "Alice",
      email: "alice@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 43,
      company_id: 73,
      name: "Carol",
      email: "carol@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 999,
      company_id: 88,
      name: "Foreign Bob",
      email: "bob@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)
    {:ok, other_scope} = Tenancy.scope(99)

    {:ok, scope: scope, other_scope: other_scope}
  end

  describe "notifiable_identity/0 and schema" do
    test "returns canonical Belimbing morph string" do
      assert User.notifiable_identity() == "App\\Core\\User\\Models\\User"
    end
  end

  describe "send_notification/3" do
    test "inserts notification with UUID primary key and polymorphic user morph type", %{
      scope: scope
    } do
      user_id = 42

      assert {:ok, %Notification{} = notification} =
               User.send_notification(scope, user_id, %{
                 title: "Welcome to Bilimbi",
                 body: "Your account is ready for use.",
                 url: "/dashboard",
                 icon: "hero-check-circle"
               })

      assert is_binary(notification.id)
      assert notification.notifiable_type == "App\\Core\\User\\Models\\User"
      assert notification.notifiable_id == 42
      assert notification.type == "generic"
      assert is_nil(notification.read_at)
      assert notification.data["title"] == "Welcome to Bilimbi"
      assert notification.data["body"] == "Your account is ready for use."
      assert notification.data["url"] == "/dashboard"
      assert notification.data["icon"] == "hero-check-circle"

      assert Notification.unread?(notification)
      refute Notification.read?(notification)
      assert Notification.title(notification) == "Welcome to Bilimbi"
      assert Notification.body(notification) == "Your account is ready for use."
      assert Notification.url(notification) == "/dashboard"
      assert Notification.icon(notification) == "hero-check-circle"
    end

    test "handles custom notification type", %{scope: scope} do
      user_id = 42

      assert {:ok, %Notification{} = notification} =
               User.send_notification(scope, user_id, %{
                 type: "App\\Notifications\\LeaveApprovedNotification",
                 data: %{
                   "title" => "Leave Request Approved",
                   "body" => "Annual leave approved by manager."
                 }
               })

      assert notification.type == "App\\Notifications\\LeaveApprovedNotification"
      assert Notification.title(notification) == "Leave Request Approved"
      assert Notification.body(notification) == "Annual leave approved by manager."
      assert Notification.icon(notification) == "hero-bell"
      assert Notification.url(notification) == nil
    end

    test "rejects notification when target user is outside tenant scope", %{
      scope: scope,
      other_scope: other_scope
    } do
      # User 999 belongs to Tenant 99, not Tenant 41
      assert {:error, :user_not_found} =
               User.send_notification(scope, 999, %{title: "Cross-tenant leak attempt"})

      # But works with other_scope
      assert {:ok, _} =
               User.send_notification(other_scope, 999, %{title: "Legitimate Tenant 99 Note"})
    end

    test "fails validation when notifiable_id is missing or non-positive" do
      assert {:error, %Ecto.Changeset{}} =
               %Notification{}
               |> Notification.changeset(%{
                 "type" => "generic",
                 "notifiable_type" => "App\\Core\\User\\Models\\User",
                 "notifiable_id" => 0,
                 "data" => %{"title" => "Invalid"}
               })
               |> Repo.insert()
    end
  end

  describe "unread_notification_count/2 and count_notifications/3" do
    test "counts unread and total notifications accurately per user within scope", %{scope: scope} do
      assert User.unread_notification_count(scope, 42) == {:ok, 0}
      assert User.count_notifications(scope, 42) == {:ok, 0}

      {:ok, n1} = User.send_notification(scope, 42, %{title: "Note 1"})
      {:ok, _n2} = User.send_notification(scope, 42, %{title: "Note 2"})
      {:ok, _n3} = User.send_notification(scope, 43, %{title: "Carol Note"})

      assert User.unread_notification_count(scope, 42) == {:ok, 2}
      assert User.count_notifications(scope, 42) == {:ok, 2}
      assert User.unread_notification_count(scope, 43) == {:ok, 1}

      User.mark_notification_as_read(scope, 42, n1.id)
      assert User.unread_notification_count(scope, 42) == {:ok, 1}
      assert User.count_notifications(scope, 42, status: :unread) == {:ok, 1}
      assert User.count_notifications(scope, 42, status: :read) == {:ok, 1}
      assert User.count_notifications(scope, 42, status: :all) == {:ok, 2}
    end

    test "fails with :user_not_found when user belongs to different tenant", %{scope: scope} do
      assert User.unread_notification_count(scope, 999) == {:error, :user_not_found}
      assert User.count_notifications(scope, 999) == {:error, :user_not_found}
    end
  end

  describe "list_notifications/3 and pagination" do
    test "lists notifications in descending order and filters by status", %{scope: scope} do
      user_id = 42

      {:ok, n1} = User.send_notification(scope, user_id, %{title: "First"})
      {:ok, n2} = User.send_notification(scope, user_id, %{title: "Second"})
      {:ok, n3} = User.send_notification(scope, user_id, %{title: "Third"})

      User.mark_notification_as_read(scope, user_id, n2.id)

      assert {:ok, all} = User.list_notifications(scope, user_id, status: :all)
      assert length(all) == 3

      assert {:ok, unread} = User.list_notifications(scope, user_id, status: :unread)
      assert length(unread) == 2
      unread_ids = Enum.map(unread, & &1.id)
      assert n1.id in unread_ids
      assert n3.id in unread_ids

      assert {:ok, read} = User.list_notifications(scope, user_id, status: :read)
      assert length(read) == 1
      assert hd(read).id == n2.id
    end

    test "supports page and per_page pagination beyond 25 items", %{scope: scope} do
      user_id = 42

      for i <- 1..30 do
        User.send_notification(scope, user_id, %{title: "Note #{i}"})
      end

      assert {:ok, page1} =
               User.list_notifications(scope, user_id, page: 1, per_page: 25)

      assert {:ok, page2} =
               User.list_notifications(scope, user_id, page: 2, per_page: 25)

      assert length(page1) == 25
      assert length(page2) == 5

      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "returns :user_not_found for foreign tenant user", %{scope: scope} do
      assert User.list_notifications(scope, 999) == {:error, :user_not_found}
    end
  end

  describe "mark_notification_as_read/3, mark_all_notifications_as_read/2, and delete_notification/3" do
    test "marks single notification as read", %{scope: scope} do
      user_id = 42
      {:ok, note} = User.send_notification(scope, user_id, %{title: "Single"})

      assert {:ok, updated} = User.mark_notification_as_read(scope, user_id, note.id)
      assert Notification.read?(updated)
      refute is_nil(updated.read_at)

      # Attempting to mark for another user returns :not_found
      assert {:error, :not_found} = User.mark_notification_as_read(scope, 43, note.id)
    end

    test "marks all unread notifications as read for a user", %{scope: scope} do
      user_id = 42
      {:ok, _n1} = User.send_notification(scope, user_id, %{title: "One"})
      {:ok, _n2} = User.send_notification(scope, user_id, %{title: "Two"})

      assert User.unread_notification_count(scope, user_id) == {:ok, 2}
      assert {:ok, 2} = User.mark_all_notifications_as_read(scope, user_id)
      assert User.unread_notification_count(scope, user_id) == {:ok, 0}
    end

    test "deletes a notification", %{scope: scope} do
      user_id = 42
      {:ok, note} = User.send_notification(scope, user_id, %{title: "To Delete"})

      assert {:ok, deleted} = User.delete_notification(scope, user_id, note.id)
      assert deleted.id == note.id
      assert {:error, :not_found} = User.get_notification(scope, user_id, note.id)
    end

    test "returns :user_not_found for foreign tenant user", %{scope: scope} do
      assert User.mark_notification_as_read(scope, 999, "any-id") == {:error, :user_not_found}
      assert User.mark_all_notifications_as_read(scope, 999) == {:error, :user_not_found}
      assert User.delete_notification(scope, 999, "any-id") == {:error, :user_not_found}
    end
  end

  describe "PubSub notification subscriptions and broadcasts" do
    test "subscribes and receives broadcasts on send, mark_read, mark_all_read, and delete", %{
      scope: scope
    } do
      user_id = 42
      assert :ok = User.subscribe_notifications(scope, user_id)

      {:ok, note} = User.send_notification(scope, user_id, %{title: "Broadcast Note"})
      assert_receive {:notification_event, {:created, %Notification{id: id}}} when id == note.id

      {:ok, _read} = User.mark_notification_as_read(scope, user_id, note.id)
      assert_receive {:notification_event, {:read, %Notification{id: id}}} when id == note.id

      {:ok, _count} = User.mark_all_notifications_as_read(scope, user_id)
      assert_receive {:notification_event, {:all_read, _count}}

      {:ok, _del} = User.delete_notification(scope, user_id, note.id)
      assert_receive {:notification_event, {:deleted, %Notification{id: id}}} when id == note.id
    end

    test "returns :ok when pubsub_server is nil", %{scope: scope} do
      with_pubsub_server(nil, fn ->
        assert :ok = User.subscribe_notifications(scope, 42)
        assert :ok = User.broadcast_notification(scope, 42, :test_event)
      end)
    end

    test "subscribing multiple times from the same process succeeds idempotently", %{scope: scope} do
      user_id = 42
      assert :ok = User.subscribe_notifications(scope, user_id)
      assert :ok = User.subscribe_notifications(scope, user_id)
    end

    test "reports a configured unavailable PubSub server without leaking its failure", %{
      scope: scope
    } do
      with_delivery_failure_telemetry(fn ->
        with_pubsub_server(__MODULE__, fn ->
          assert {:error, :pubsub_unavailable} = User.subscribe_notifications(scope, 42)

          assert_receive {@notification_delivery_failure_event, %{count: 1},
                          %{operation: :subscribe}}

          assert {:error, :pubsub_unavailable} =
                   User.broadcast_notification(scope, 42, {:created, %{private: "payload"}})

          assert_receive {@notification_delivery_failure_event, %{count: 1},
                          %{operation: :broadcast}}
        end)
      end)
    end

    test "keeps committed notification mutations successful when delivery is unavailable", %{
      scope: scope
    } do
      with_delivery_failure_telemetry(fn ->
        with_pubsub_server(__MODULE__, fn ->
          assert {:ok, created} = User.send_notification(scope, 42, %{title: "Created once"})
          assert {:ok, [persisted]} = User.list_notifications(scope, 42)
          assert persisted.id == created.id
          assert_delivery_failure(:broadcast)

          assert {:ok, read} = User.mark_notification_as_read(scope, 42, created.id)
          assert Notification.read?(read)
          assert_delivery_failure(:broadcast)

          assert {:ok, second} = User.send_notification(scope, 42, %{title: "Read all"})
          assert_delivery_failure(:broadcast)

          assert {:ok, 1} = User.mark_all_notifications_as_read(scope, 42)
          assert_delivery_failure(:broadcast)

          assert {:ok, deleted} = User.delete_notification(scope, 42, second.id)
          assert deleted.id == second.id
          assert {:error, :not_found} = User.get_notification(scope, 42, second.id)
          assert_delivery_failure(:broadcast)
        end)
      end)
    end
  end

  defp assert_delivery_failure(operation) do
    assert_receive {@notification_delivery_failure_event, %{count: 1}, %{operation: ^operation}}
  end

  defp with_delivery_failure_telemetry(fun) do
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        @notification_delivery_failure_event,
        fn event, measurements, metadata, test_pid ->
          send(test_pid, {event, measurements, metadata})
        end,
        self()
      )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end
  end

  defp with_pubsub_server(server, fun) do
    previous = Application.fetch_env(:bilimbi_core_user, :pubsub_server)
    Application.put_env(:bilimbi_core_user, :pubsub_server, server)

    try do
      fun.()
    after
      case previous do
        {:ok, value} -> Application.put_env(:bilimbi_core_user, :pubsub_server, value)
        :error -> Application.delete_env(:bilimbi_core_user, :pubsub_server)
      end
    end
  end
end
