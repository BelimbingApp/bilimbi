defmodule Bilimbi.Core.User.Notifications do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Notification

  @notification_delivery_failure_event [:bilimbi, :core, :user, :notification_delivery, :failed]

  defp pubsub_server do
    Application.get_env(:bilimbi_core_user, :pubsub_server)
  end

  @doc "Topic name for PubSub notification events per tenant and user."
  @spec notification_topic(pos_integer(), pos_integer()) :: String.t()
  def notification_topic(tenant_id, user_id)
      when is_integer(tenant_id) and is_integer(user_id) do
    "user_notifications:#{tenant_id}:#{user_id}"
  end

  @doc "Subscribes the calling process to notifications for the given user in tenant scope."
  @spec subscribe_notifications(Scope.t(), pos_integer()) :: :ok | {:error, :pubsub_unavailable}
  def subscribe_notifications(%Scope{tenant: %{id: tenant_id}}, user_id)
      when is_integer(user_id) do
    if server = pubsub_server() do
      # No special case for a second subscribe from the same process.
      # `Phoenix.PubSub.subscribe/3` is `Registry.register/3` against a registry
      # declared `keys: :duplicate` (phoenix_pubsub supervisor.ex:31), which is
      # how many processes share one topic — it never answers
      # `{:already_registered, _}`. A process that subscribes twice is
      # registered twice and receives every event twice, which is what #425
      # guards against at the mount path where it can actually happen.
      notification_pubsub(:subscribe, fn ->
        Phoenix.PubSub.subscribe(server, notification_topic(tenant_id, user_id))
      end)
    else
      :ok
    end
  end

  @doc """
  Broadcasts a notification change event to subscribers.

  A configured unavailable PubSub transport returns a bounded error and emits a
  redacted telemetry event. Notification mutations that have already committed
  preserve their successful result when that delivery fails.
  """
  @spec broadcast_notification(Scope.t(), pos_integer(), term()) ::
          :ok | {:error, :pubsub_unavailable}
  def broadcast_notification(%Scope{tenant: %{id: tenant_id}}, user_id, event)
      when is_integer(user_id) do
    if server = pubsub_server() do
      notification_pubsub(:broadcast, fn ->
        Phoenix.PubSub.broadcast(
          server,
          notification_topic(tenant_id, user_id),
          {:notification_event, event}
        )
      end)
    else
      :ok
    end
  end

  @doc """
  Sends an in-app database notification to a user within tenant scope.
  `attrs` can be a map with `:title`, `:body`, `:url`, `:icon`, `:type`, `:data`, etc.
  """
  @spec send_notification(Scope.t(), pos_integer(), map()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | Changeset.t()}
  def send_notification(%Scope{} = scope, user_id, attrs)
      when is_integer(user_id) and user_id > 0 and is_map(attrs) do
    with {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      type = Map.get(attrs, "type") || Map.get(attrs, :type) || "generic"

      data =
        cond do
          is_map(attrs["data"]) ->
            attrs["data"]

          is_map(attrs[:data]) ->
            attrs[:data]

          true ->
            attrs
            |> Map.drop(["type", :type, "id", :id, "read_at", :read_at])
        end

      params = %{
        "type" => to_string(type),
        "notifiable_type" => User.notifiable_identity(),
        "notifiable_id" => user_id,
        "data" => data
      }

      case %Notification{} |> Notification.changeset(params) |> Repo.insert() do
        {:ok, notification} ->
          broadcast_notification(scope, user_id, {:created, notification})
          {:ok, notification}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Lists notifications for a user within tenant scope, ordered by creation descending.
  Options:
    - `:status` - `:all` (default), `:unread`, or `:read`
    - `:page` - positive integer (default nil)
    - `:per_page` - positive integer (default 25)
    - `:limit` - positive integer or nil (default nil)
    - `:offset` - non-negative integer (default 0)
  """
  @spec list_notifications(Scope.t(), keyword()) ::
          {:ok, [Notification.t()]} | {:error, :user_not_found | :unauthorized}
  def list_notifications(%Scope{} = scope, opts \\ []) when is_list(opts) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      status = Keyword.get(opts, :status, :all)
      page = Keyword.get(opts, :page)
      per_page = Keyword.get(opts, :per_page, 25)
      limit = Keyword.get(opts, :limit)
      offset = Keyword.get(opts, :offset, 0)
      morph = User.notifiable_identity()

      query =
        from(n in Notification,
          where: n.notifiable_type == ^morph and n.notifiable_id == ^user_id,
          order_by: [desc: n.created_at, desc: n.id]
        )

      query =
        case status do
          :unread -> from(n in query, where: is_nil(n.read_at))
          :read -> from(n in query, where: not is_nil(n.read_at))
          _ -> query
        end

      query =
        cond do
          is_integer(page) and page > 0 ->
            from(n in query, limit: ^per_page, offset: ^((page - 1) * per_page))

          is_integer(limit) and limit > 0 ->
            from(n in query, limit: ^limit, offset: ^offset)

          true ->
            query
        end

      {:ok, Repo.all(query)}
    end
  end

  @doc """
  Counts total notifications for a user under given status within tenant scope.
  """
  @spec count_notifications(Scope.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  def count_notifications(%Scope{} = scope, opts \\ []) when is_list(opts) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      status = Keyword.get(opts, :status, :all)
      morph = User.notifiable_identity()

      query =
        from(n in Notification,
          where: n.notifiable_type == ^morph and n.notifiable_id == ^user_id
        )

      query =
        case status do
          :unread -> from(n in query, where: is_nil(n.read_at))
          :read -> from(n in query, where: not is_nil(n.read_at))
          _ -> query
        end

      {:ok, Repo.aggregate(query, :count, :id)}
    end
  end

  @doc "Returns the count of unread notifications for a user within tenant scope."
  @spec unread_notification_count(Scope.t()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  def unread_notification_count(%Scope{} = scope) do
    count_notifications(scope, status: :unread)
  end

  @doc "Gets a notification by UUID for a specific user within tenant scope."
  @spec get_notification(Scope.t(), binary()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | :not_found | :unauthorized}
  def get_notification(%Scope{} = scope, notification_id)
      when is_binary(notification_id) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      morph = User.notifiable_identity()

      query =
        from(n in Notification,
          where:
            n.notifiable_type == ^morph and n.notifiable_id == ^user_id and
              n.id == ^notification_id
        )

      case Repo.one(query) do
        nil -> {:error, :not_found}
        notification -> {:ok, notification}
      end
    end
  end

  @doc "Marks a specific notification as read for a user within tenant scope."
  @spec mark_notification_as_read(Scope.t(), binary()) ::
          {:ok, Notification.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  def mark_notification_as_read(%Scope{} = scope, notification_id)
      when is_binary(notification_id) do
    with {:ok, notification} <- get_notification(scope, notification_id) do
      if Notification.read?(notification) do
        {:ok, notification}
      else
        case notification |> Notification.mark_read_changeset() |> Repo.update() do
          {:ok, updated} ->
            broadcast_notification(scope, updated.notifiable_id, {:read, updated})
            {:ok, updated}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    end
  end

  @doc "Marks all unread notifications as read for a user within tenant scope."
  @spec mark_all_notifications_as_read(Scope.t()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  def mark_all_notifications_as_read(%Scope{} = scope) do
    with {:ok, user_id} <- subject(scope),
         {:ok, _user} <- User.get_tenant_user(scope, user_id) do
      morph = User.notifiable_identity()
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # A read receipt on the actor's own notifications: high volume, and
      # it records nothing about the business the notifications are about.
      {count, _} =
        Audit.without_auditing(fn ->
          from(n in Notification,
            where:
              n.notifiable_type == ^morph and n.notifiable_id == ^user_id and is_nil(n.read_at)
          )
          |> Repo.update_all(set: [read_at: now, updated_at: now])
        end)

      broadcast_notification(scope, user_id, {:all_read, count})
      {:ok, count}
    end
  end

  @doc "Deletes a notification for a user within tenant scope."
  @spec delete_notification(Scope.t(), binary()) ::
          {:ok, Notification.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  def delete_notification(%Scope{} = scope, notification_id)
      when is_binary(notification_id) do
    with {:ok, notification} <- get_notification(scope, notification_id) do
      case Repo.delete(notification) do
        {:ok, deleted} ->
          broadcast_notification(scope, deleted.notifiable_id, {:deleted, deleted})
          {:ok, deleted}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp notification_pubsub(operation, delivery) do
    case delivery.() do
      :ok -> :ok
      {:error, _reason} -> notification_delivery_failed(operation)
    end
  rescue
    _exception in ArgumentError -> notification_delivery_failed(operation)
  end

  defp notification_delivery_failed(operation) do
    :telemetry.execute(@notification_delivery_failure_event, %{count: 1}, %{operation: operation})
    {:error, :pubsub_unavailable}
  end

  defp subject(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id} when is_integer(user_id) and user_id > 0 ->
        {:ok, user_id}

      %TenancyActor{} ->
        {:error, :unauthorized}
    end
  end
end
