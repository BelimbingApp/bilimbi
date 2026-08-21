defmodule Bilimbi.Core.User do
  @moduledoc """
  Public API for user accounts, credentials, and user-owned preferences.

  Tenant-owned operations run under a `Bilimbi.Base.Tenancy.Scope`, so the
  tenant is proven once at the edge. Login and password-reset lookup are the
  deliberate exceptions: before authentication there is no tenant scope, and
  the globally unique email is the credential identity. Ecto schemas and
  stored credentials stay private to this deep module.

  Tenancy here is *derived*, not stored. `users` has no `tenant_id` column and
  no soft delete; a user reaches a tenant only through its nullable
  `company_id`. Belimbing's own list
  (`app/Core/User/Livewire/Users/Index.php:110-111`) left-joins `companies` and
  filters `companies.tenant_id`, so a user with no company is invisible to
  every tenant-scoped read. Single-company reads go through
  `Company.get_company/2`; the tenant-wide list goes through
  `Company.list_tenant_company_ids/1` so this module never queries `companies`.

  Soft-deleted companies: Belimbing's raw join still returns those users.
  Bilimbi matches that visibility (BLB-S1-010 option a) via company ids that
  include soft-deleted rows. Live-only company presentation remains
  `Company.list_companies/1`.

  New credentials are Argon2id. Existing Laravel Argon2 hashes are verified in
  place, while legacy `$2y$` bcrypt credentials are verified compatibly and
  upgraded to Argon2id after a successful login. Callers supply plaintext only
  under `:password`; pre-hashed input is never accepted by the public API.

  This module provides lifecycle primitives, not public routes. Bilimbi keeps
  Belimbing's policy of no public self-registration; Web decides which trusted
  administrative workflows may call `register_user/3`.
  """

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Actor, as: AuthzActor
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.DatabaseQuery
  alias Bilimbi.Core.User.EmailVerification
  alias Bilimbi.Core.User.Notification
  alias Bilimbi.Core.User.Password
  alias Bilimbi.Core.User.PasswordResetToken
  alias Bilimbi.Core.User.Pin
  alias Bilimbi.Core.User.Schema
  alias Bilimbi.Core.User.Summary
  alias Ecto.Changeset

  @type lookup_error ::
          :company_not_found
          | :user_not_found
          | :employee_not_found
          | :not_platform_operator
          | :unauthorized
  @type credential_error :: :invalid_credentials | :credential_upgrade_failed

  @preference_keys [
    "ai.last_used_model_hints",
    "ui.dashboard.layout",
    "ui.dashboard.sections",
    "ui.landing_menu_id",
    "ui.theme"
  ]

  @password_reset_max_age 3_600
  @password_reset_throttle 60
  @notification_delivery_failure_event [:bilimbi, :core, :user, :notification_delivery, :failed]

  @doc """
  Lists the users affiliated with one company inside the scope's tenant.

  Ordered by id. A user whose `company_id` is nil belongs to no company and so
  appears in no company list, matching Belimbing.
  """
  @spec list_company_users(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_company_users(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      users =
        from(user in Schema,
          where: user.company_id == ^company_id,
          order_by: user.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, users}
    end
  end

  @doc """
  Lists every user visible to the scope's tenant, ordered by id.

  Visibility matches Belimbing's tenant-wide list: affiliation is through any
  company owned by the tenant, including soft-deleted companies. Users with a
  null `company_id` never appear. Company membership is resolved only through
  `Company.list_tenant_company_ids/1`.
  """
  @spec list_users(Scope.t()) :: {:ok, [Summary.t()]}
  def list_users(%Scope{} = scope) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    users =
      case company_ids do
        [] ->
          []

        ids ->
          from(user in Schema,
            where: user.company_id in ^ids,
            order_by: user.id
          )
          |> Repo.all()
          |> Enum.map(&Summary.from_schema/1)
      end

    {:ok, users}
  end

  @spec get_user(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error()}
  def get_user(%Scope{} = scope, company_id, user_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, Summary.from_schema(user)}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @doc """
  Reads one user under the scope's tenant-wide visibility.

  This is the detail companion to `list_users/1`: it finds any user the
  tenant list would return, including one whose owning company is
  soft-deleted. Writes stay on the per-company operations, which still
  require a live owning company; a caller that needs to mutate must resolve
  through `get_user/3` and accept its `:company_not_found`.
  """
  @spec get_tenant_user(Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :user_not_found}
  def get_tenant_user(%Scope{} = scope, user_id) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    case company_ids do
      [] ->
        {:error, :user_not_found}

      ids ->
        case Repo.get_by(Schema, id: user_id) do
          %Schema{company_id: company_id} = user
          when is_integer(company_id) ->
            if company_id in ids do
              {:ok, Summary.from_schema(user)}
            else
              {:error, :user_not_found}
            end

          _other ->
            {:error, :user_not_found}
        end
    end
  end

  @doc """
  Reads multiple users by ID under the scope's tenant-wide visibility.

  Returns `{:ok, map}` where keys are user IDs and values are `Summary` structs.
  Non-existent IDs and users outside the tenant's visible companies are omitted.
  """
  @spec get_tenant_users(Scope.t(), [pos_integer()]) :: {:ok, %{pos_integer() => Summary.t()}}
  def get_tenant_users(%Scope{} = scope, user_ids) when is_list(user_ids) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    case company_ids do
      [] ->
        {:ok, %{}}

      ids ->
        users =
          from(user in Schema,
            where: user.id in ^user_ids and user.company_id in ^ids
          )
          |> Repo.all()
          |> Enum.map(&Summary.from_schema/1)
          |> Map.new(&{&1.id, &1})

        {:ok, users}
    end
  end

  @doc "Creates an unverified account; Web must not expose this as public self-registration."
  @spec create_user(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | Changeset.t()}
  def create_user(%Scope{} = scope, company_id, attributes) do
    register_user(scope, company_id, attributes)
  end

  @doc "Creates an unverified account and hashes its plaintext `:password` with Argon2id."
  @spec register_user(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | Changeset.t()}
  def register_user(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      company_id
      |> Schema.creation_changeset(attributes)
      |> validate_employee(scope, company_id)
      |> persist_insert()
    end
  end

  @doc "Authenticates the globally unique email and upgrades legacy bcrypt on success."
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Summary.t()} | {:error, credential_error()}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(Schema, email: Schema.normalize_email(email))

    if user && Password.valid?(password, user.password_hash) do
      case maybe_upgrade_credential(user, password) do
        {:ok, user} -> {:ok, Summary.from_schema(user)}
        {:error, _changeset} -> {:error, :credential_upgrade_failed}
      end
    else
      if is_nil(user), do: Password.no_user_verify()
      {:error, :invalid_credentials}
    end
  end

  @doc "Checks an authenticated user's current password inside the proven company boundary."
  @spec confirm_password(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          :ok | {:error, lookup_error() | :invalid_password}
  def confirm_password(%Scope{} = scope, company_id, user_id, password)
      when is_binary(password) do
    with {:ok, user} <- scoped_user(scope, company_id, user_id) do
      if Password.valid?(password, user.password_hash),
        do: :ok,
        else: {:error, :invalid_password}
    end
  end

  @doc "Replaces a password only after verifying the current credential."
  @spec change_password(Scope.t(), pos_integer(), pos_integer(), String.t(), String.t()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | :invalid_password | Changeset.t()}
  def change_password(%Scope{} = scope, company_id, user_id, current_password, new_password)
      when is_binary(current_password) and is_binary(new_password) do
    with {:ok, user} <- scoped_user(scope, company_id, user_id),
         true <- Password.valid?(current_password, user.password_hash) do
      user
      |> Schema.password_changeset(%{password: new_password})
      |> persist_update()
    else
      false -> {:error, :invalid_password}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Stores a one-time reset token and passes its plaintext only to `deliver_fun`.

  Unknown accounts and throttled requests both return `:ok`, so a public
  caller can always give the same response. Delivery receives a safe
  `Summary` and the plaintext token; the database stores only its hash.
  """
  @spec request_password_reset(
          String.t(),
          (Summary.t(), String.t() -> :ok | {:error, term()}),
          keyword()
        ) :: :ok | {:error, Changeset.t() | {:delivery_failed, term()}}
  def request_password_reset(email, deliver_fun, opts \\ [])
      when is_binary(email) and is_function(deliver_fun, 2) and is_list(opts) do
    opts = Keyword.validate!(opts, throttle_seconds: @password_reset_throttle)
    throttle_seconds = non_negative_seconds!(opts[:throttle_seconds], :throttle_seconds)
    email = Schema.normalize_email(email)

    case Repo.get_by(Schema, email: email) do
      nil ->
        random_token() |> Password.hash()
        :ok

      user ->
        if reset_throttled?(email, throttle_seconds) do
          :ok
        else
          issue_password_reset(user, deliver_fun)
        end
    end
  end

  @doc "Consumes a valid reset token, replaces the password, and rotates `remember_token`."
  @spec reset_password(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Summary.t()} | {:error, :invalid_or_expired_token | Changeset.t()}
  def reset_password(email, token, new_password, opts \\ [])
      when is_binary(email) and is_binary(token) and is_binary(new_password) and is_list(opts) do
    opts = Keyword.validate!(opts, max_age: @password_reset_max_age)
    max_age = positive_seconds!(opts[:max_age], :max_age)
    email = Schema.normalize_email(email)

    with {:ok, user} <- valid_password_reset(email, token, max_age),
         %Changeset{valid?: true} = changeset <-
           Schema.password_changeset(user, %{password: new_password}) do
      password_hash = Changeset.get_change(changeset, :password_hash)
      remember_token = random_remember_token()

      Repo.transaction(fn ->
        case Repo.update(Schema.password_reset_changeset(user, password_hash, remember_token)) do
          {:ok, updated} ->
            Repo.delete_all(from(reset in PasswordResetToken, where: reset.email == ^email))
            Summary.from_schema(updated)

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
      |> case do
        {:ok, summary} -> {:ok, summary}
        {:error, %Changeset{} = changeset} -> {:error, changeset}
      end
    else
      %Changeset{} = changeset -> {:error, changeset}
      {:error, :invalid_or_expired_token} = error -> error
    end
  end

  @doc "Issues a signed, expiring token bound to the user's current email address."
  @spec issue_email_verification_token(
          Scope.t(),
          pos_integer(),
          pos_integer(),
          String.t(),
          keyword()
        ) :: {:ok, String.t()} | {:error, lookup_error() | :already_verified}
  def issue_email_verification_token(%Scope{} = scope, company_id, user_id, secret, opts \\ []) do
    with {:ok, user} <- scoped_user(scope, company_id, user_id) do
      if user.email_verified_at do
        {:error, :already_verified}
      else
        {:ok, EmailVerification.sign(user.id, user.email, secret, opts)}
      end
    end
  end

  @doc "Verifies a signed token and marks the unchanged email address as verified."
  @spec verify_email(Scope.t(), pos_integer(), String.t(), String.t(), keyword()) ::
          {:ok, :verified | :already_verified, Summary.t()}
          | {:error, :company_not_found | :invalid_or_expired_token | Changeset.t()}
  def verify_email(%Scope{} = scope, company_id, token, secret, opts \\ []) do
    with {:ok, {user_id, email}} <- EmailVerification.verify(token, secret, opts),
         {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id),
         true <- Plug.Crypto.secure_compare(user.email, email) do
      if user.email_verified_at do
        {:ok, :already_verified, Summary.from_schema(user)}
      else
        case Repo.update(Schema.verify_email_changeset(user, now())) do
          {:ok, updated} -> {:ok, :verified, Summary.from_schema(updated)}
          {:error, changeset} -> {:error, changeset}
        end
      end
    else
      {:error, :company_not_found} = error -> error
      _invalid -> {:error, :invalid_or_expired_token}
    end
  end

  @doc "Returns the module-owned preferences resolved at user scope."
  @spec user_preferences(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, %{required(String.t()) => term()}} | {:error, lookup_error()}
  def user_preferences(%Scope{} = scope, company_id, user_id) do
    with {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      {:ok, Settings.get_many(@preference_keys, settings_scope)}
    end
  end

  @doc "Reads one module-owned preference at user scope."
  @spec get_user_preference(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, term()} | {:error, lookup_error() | :unsupported_preference}
  def get_user_preference(%Scope{} = scope, company_id, user_id, key) when is_binary(key) do
    with :ok <- supported_preference(key),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      {:ok, Settings.get(key, settings_scope)}
    end
  end

  @doc "Stores one validated module-owned preference at user scope."
  @spec put_user_preference(Scope.t(), pos_integer(), pos_integer(), String.t(), term()) ::
          {:ok, term()}
          | {:error,
             lookup_error() | :unsupported_preference | :invalid_preference | Changeset.t()}
  def put_user_preference(%Scope{} = scope, company_id, user_id, key, value)
      when is_binary(key) do
    with :ok <- supported_preference(key),
         :ok <- valid_preference(key, value),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      Settings.put(key, value, settings_scope)
    end
  end

  @doc "Deletes one user override so the module-owned default resolves again."
  @spec delete_user_preference(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          :ok | {:error, lookup_error() | :unsupported_preference}
  def delete_user_preference(%Scope{} = scope, company_id, user_id, key)
      when is_binary(key) do
    with :ok <- supported_preference(key),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      Settings.delete(key, settings_scope)
    end
  end

  @doc "Lists all pinned items for a user ordered by sort_order."
  @spec list_user_pins(pos_integer()) :: [Pin.t()]
  def list_user_pins(user_id) when is_integer(user_id) and user_id > 0 do
    from(p in Pin,
      where: p.user_id == ^user_id,
      order_by: [asc: p.sort_order, asc: p.id]
    )
    |> Repo.all()
  end

  @doc """
  Toggles a pinned item for a user.

  If a pin with the same normalized URL already exists, it is deleted.
  Otherwise, a new pin is appended with the next sort_order value.
  Returns `{:ok, :pinned | :unpinned, [Pin.t()]}` or `{:error, Changeset.t()}`.
  """
  @spec toggle_user_pin(pos_integer(), map()) ::
          {:ok, :pinned | :unpinned, [Pin.t()]} | {:error, Changeset.t()}
  def toggle_user_pin(user_id, attrs)
      when is_integer(user_id) and user_id > 0 and is_map(attrs) do
    url = Map.get(attrs, "url") || Map.get(attrs, :url) || ""
    url_hash = Pin.hash_url(to_string(url))

    existing =
      from(p in Pin,
        where: p.user_id == ^user_id and p.url_hash == ^url_hash
      )
      |> Repo.one()

    case existing do
      %Pin{} = pin ->
        with {:ok, _deleted} <- Repo.delete(pin) do
          {:ok, :unpinned, list_user_pins(user_id)}
        end

      nil ->
        max_order =
          from(p in Pin,
            where: p.user_id == ^user_id,
            select: max(p.sort_order)
          )
          |> Repo.one() || -1

        attrs_with_defaults =
          attrs
          |> Map.put("user_id", user_id)
          |> Map.put_new("sort_order", max_order + 1)

        %Pin{}
        |> Pin.changeset(attrs_with_defaults)
        |> Repo.insert()
        |> case do
          {:ok, _pin} -> {:ok, :pinned, list_user_pins(user_id)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Reorders a user's pinned items according to a list of ordered pin IDs.
  Returns `{:ok, [Pin.t()]}`.
  """
  @spec reorder_user_pins(pos_integer(), [pos_integer()]) :: {:ok, [Pin.t()]}
  def reorder_user_pins(user_id, ordered_pin_ids)
      when is_integer(user_id) and user_id > 0 and is_list(ordered_pin_ids) do
    Repo.transaction(fn ->
      Enum.each(Enum.with_index(ordered_pin_ids), fn {pin_id, index} ->
        from(p in Pin,
          where: p.user_id == ^user_id and p.id == ^pin_id
        )
        |> Repo.update_all(set: [sort_order: index])
      end)

      list_user_pins(user_id)
    end)
  end

  # =========================================================================
  # In-App Notifications
  # =========================================================================

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
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
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
        "notifiable_type" => notifiable_identity(),
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
  @spec list_notifications(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [Notification.t()]} | {:error, :user_not_found}
  def list_notifications(%Scope{} = scope, user_id, opts \\ [])
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      status = Keyword.get(opts, :status, :all)
      page = Keyword.get(opts, :page)
      per_page = Keyword.get(opts, :per_page, 25)
      limit = Keyword.get(opts, :limit)
      offset = Keyword.get(opts, :offset, 0)
      morph = notifiable_identity()

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
  @spec count_notifications(Scope.t(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found}
  def count_notifications(%Scope{} = scope, user_id, opts \\ [])
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      status = Keyword.get(opts, :status, :all)
      morph = notifiable_identity()

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
  @spec unread_notification_count(Scope.t(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found}
  def unread_notification_count(%Scope{} = scope, user_id)
      when is_integer(user_id) and user_id > 0 do
    count_notifications(scope, user_id, status: :unread)
  end

  @doc "Gets a notification by UUID for a specific user within tenant scope."
  @spec get_notification(Scope.t(), pos_integer(), binary()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | :not_found}
  def get_notification(%Scope{} = scope, user_id, notification_id)
      when is_integer(user_id) and user_id > 0 and is_binary(notification_id) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      morph = notifiable_identity()

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
  @spec mark_notification_as_read(Scope.t(), pos_integer(), binary()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | :not_found | Changeset.t()}
  def mark_notification_as_read(%Scope{} = scope, user_id, notification_id)
      when is_integer(user_id) and user_id > 0 and is_binary(notification_id) do
    with {:ok, notification} <- get_notification(scope, user_id, notification_id) do
      if Notification.read?(notification) do
        {:ok, notification}
      else
        case notification |> Notification.mark_read_changeset() |> Repo.update() do
          {:ok, updated} ->
            broadcast_notification(scope, user_id, {:read, updated})
            {:ok, updated}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    end
  end

  @doc "Marks all unread notifications as read for a user within tenant scope."
  @spec mark_all_notifications_as_read(Scope.t(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found}
  def mark_all_notifications_as_read(%Scope{} = scope, user_id)
      when is_integer(user_id) and user_id > 0 do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      morph = notifiable_identity()
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {count, _} =
        from(n in Notification,
          where: n.notifiable_type == ^morph and n.notifiable_id == ^user_id and is_nil(n.read_at)
        )
        |> Repo.update_all(set: [read_at: now, updated_at: now])

      broadcast_notification(scope, user_id, {:all_read, count})
      {:ok, count}
    end
  end

  @doc "Deletes a notification for a user within tenant scope."
  @spec delete_notification(Scope.t(), pos_integer(), binary()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | :not_found | Changeset.t()}
  def delete_notification(%Scope{} = scope, user_id, notification_id)
      when is_integer(user_id) and user_id > 0 and is_binary(notification_id) do
    with {:ok, notification} <- get_notification(scope, user_id, notification_id) do
      case Repo.delete(notification) do
        {:ok, deleted} ->
          broadcast_notification(scope, user_id, {:deleted, deleted})
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

  @spec update_user(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def update_user(%Scope{} = scope, company_id, user_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      user
      |> Schema.update_changeset(attributes)
      |> validate_employee(scope, company_id)
      |> persist_update()
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @doc """
  Replaces the account linked to an employee.

  This is the User-owned half of the employee account workflow.  It locks the
  employee affiliation and every affected account before changing the link, so
  replacing a link cannot leave two accounts attached to one employee.
  """
  @spec replace_employee_account(Scope.t(), pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok, Summary.t() | nil}
          | {:error, lookup_error() | :employee_not_found | Changeset.t()}
  def replace_employee_account(%Scope{} = scope, company_id, employee_id, user_id)
      when is_integer(company_id) and is_integer(employee_id) do
    Repo.transaction(fn ->
      with {:ok, _company} <- lock_target_company(scope, company_id),
           {:ok, _proof} <- maybe_lock_employee(scope, company_id, employee_id),
           {:ok, employee} <- Employee.get_employee(scope, company_id, employee_id),
           :ok <- reject_agent_account(employee, user_id),
           {:ok, linked_users} <- lock_employee_users(company_id, employee_id),
           {:ok, target_user} <- lock_replacement_user(company_id, user_id, employee_id),
           :ok <- clear_employee_users(linked_users, target_user),
           {:ok, linked} <- attach_employee(target_user, employee_id) do
        linked
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> transaction_result()
  end

  @doc """
  Changes an employee type while preserving the no-account-on-agent invariant.

  The employee page owns the interaction; this User-owned coordinator owns the
  cross-module account mutation.  Both writes run in the one shared Repo
  transaction, so an invalid or refused employee update rolls the unlink back.
  """
  @spec change_employee_type(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, Bilimbi.Core.Employee.Summary.t()}
          | {:error, lookup_error() | :employee_not_found | Changeset.t()}
  def change_employee_type(%Scope{} = scope, company_id, employee_id, type)
      when is_integer(company_id) and is_integer(employee_id) and is_binary(type) do
    Repo.transaction(fn ->
      with {:ok, _company} <- lock_target_company(scope, company_id),
           {:ok, _proof} <- maybe_lock_employee(scope, company_id, employee_id),
           {:ok, linked_users} <- lock_employee_users(company_id, employee_id),
           :ok <- maybe_clear_agent_accounts(linked_users, type),
           {:ok, employee} <-
             Employee.update_employee(scope, company_id, employee_id, %{employee_type: type}) do
        employee
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> transaction_result()
  end

  @spec delete_user(Scope.t(), pos_integer(), pos_integer()) :: :ok | {:error, lookup_error()}
  def delete_user(%Scope{} = scope, company_id, user_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, _} = Repo.delete(user)
      :ok
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @doc """
  Lists unaffiliated users (both `company_id` and `employee_id` are nil).

  Accessible only to platform operators with the `admin.user.unaffiliated.manage`
  capability. Unaffiliated users belong to no tenant and are invisible to
  ordinary tenant-scoped queries.
  """
  @spec list_unaffiliated_users(AuthzActor.t(), Scope.t()) ::
          {:ok, [Summary.t()]} | {:error, :not_platform_operator | :unauthorized}
  def list_unaffiliated_users(%AuthzActor{} = actor, %Scope{} = scope) do
    with :ok <- verify_platform_operator(scope),
         :ok <- authorize_unaffiliated(actor, scope) do
      users =
        from(user in Schema,
          where: is_nil(user.company_id) and is_nil(user.employee_id),
          order_by: user.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, users}
    end
  end

  @doc """
  Reads one unaffiliated user.

  Fails closed as `{:error, :user_not_found}` if the user is missing, not
  unaffiliated, or if the caller is not an authorized platform operator.
  """
  @spec get_unaffiliated_user(AuthzActor.t(), Scope.t(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, :user_not_found}
  def get_unaffiliated_user(%AuthzActor{} = actor, %Scope{} = scope, user_id)
      when is_integer(user_id) and user_id > 0 do
    with :ok <- verify_platform_operator(scope),
         :ok <- authorize_unaffiliated(actor, scope, user_id),
         %Schema{} = user <-
           Repo.one(
             from(u in Schema,
               where: u.id == ^user_id and is_nil(u.company_id) and is_nil(u.employee_id)
             )
           ) do
      {:ok, Summary.from_schema(user)}
    else
      _error -> {:error, :user_not_found}
    end
  end

  def get_unaffiliated_user(%AuthzActor{}, %Scope{}, _user_id), do: {:error, :user_not_found}

  @doc """
  Creates an unaffiliated user account with no company or employee affiliation.

  Hashes the plaintext `:password` with Argon2id. Accessible only to platform
  operators. Records an audit mutation atomically.
  """
  @spec create_unaffiliated_user(AuthzActor.t(), Scope.t(), map()) ::
          {:ok, Summary.t()} | {:error, :not_platform_operator | :unauthorized | Changeset.t()}
  def create_unaffiliated_user(%AuthzActor{} = actor, %Scope{} = scope, attributes)
      when is_map(attributes) do
    with :ok <- verify_platform_operator(scope),
         :ok <- authorize_unaffiliated(actor, scope) do
      changeset =
        nil
        |> Schema.creation_changeset(attributes)
        |> Changeset.put_change(:employee_id, nil)

      Repo.transaction(fn ->
        with {:ok, %Schema{} = user} <- Repo.insert(changeset),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
                 actor,
                 user.id,
                 "created_unaffiliated",
                 nil,
                 %{},
                 %{"name" => user.name, "email" => user.email}
               ) do
          Summary.from_schema(user)
        else
          {:error, %Changeset{} = err_changeset} -> Repo.rollback(err_changeset)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Assigns an unaffiliated user to a live company in the target tenant scope.

  If an optional `employee_id` is supplied, validates and locks that employee's
  affiliation to the target company. Requires platform operator authority.
  Terminates existing sessions for this user and records an atomic audit mutation.
  """
  @spec assign_unaffiliated_user(
          AuthzActor.t(),
          Scope.t(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :employee_not_found | :unauthorized | Changeset.t()}
  def assign_unaffiliated_user(actor, scope, user_id, target_company_id, opts \\ [])

  def assign_unaffiliated_user(
        %AuthzActor{} = actor,
        %Scope{} = scope,
        user_id,
        target_company_id,
        opts
      )
      when is_integer(user_id) and user_id > 0 and is_integer(target_company_id) and
             target_company_id > 0 and is_list(opts) do
    employee_id = Keyword.get(opts, :employee_id)
    current_session_id = Keyword.get(opts, :current_session_id, "revoke-unaffiliated-assign")

    with :ok <- verify_platform_operator(scope),
         :ok <- authorize_unaffiliated(actor, scope, user_id) do
      Repo.transaction(fn ->
        with {:ok, _company_proof} <- lock_target_company(scope, target_company_id),
             {:ok, _emp_proof} <- maybe_lock_employee(scope, target_company_id, employee_id),
             {:ok, user} <- lock_unaffiliated_user(user_id),
             {:ok, updated_user} <-
               user
               |> Changeset.change(company_id: target_company_id, employee_id: employee_id)
               |> Repo.update(),
             {:ok, _terminated_count} <-
               Session.terminate_user_sessions(user.id, current_session_id),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
                 actor,
                 user.id,
                 "assigned_company",
                 target_company_id,
                 %{"company_id" => nil, "employee_id" => nil},
                 %{"company_id" => target_company_id, "employee_id" => employee_id}
               ) do
          Summary.from_schema(updated_user)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def assign_unaffiliated_user(%AuthzActor{}, %Scope{}, user_id, _target_company_id, opts)
      when not (is_integer(user_id) and user_id > 0) and is_list(opts),
      do: {:error, :user_not_found}

  def assign_unaffiliated_user(%AuthzActor{}, %Scope{}, _user_id, target_company_id, opts)
      when not (is_integer(target_company_id) and target_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  @doc """
  Reassigns a user from one live company to another within the proven tenant scope.

  Locks both companies in ascending ID order before taking the User row lock.
  If an `employee_id` is passed, validates and locks it against the target company;
  otherwise clears the employee link so no cross-company employee association remains.
  Terminates existing sessions and records an atomic audit mutation.
  """
  @spec reassign_user_company(
          AuthzActor.t(),
          Scope.t(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :employee_not_found | :unauthorized | Changeset.t()}
  def reassign_user_company(
        actor,
        scope,
        current_company_id,
        user_id,
        target_company_id,
        opts \\ []
      )

  def reassign_user_company(
        %AuthzActor{} = actor,
        %Scope{} = scope,
        current_company_id,
        user_id,
        target_company_id,
        opts
      )
      when is_integer(current_company_id) and current_company_id > 0 and
             is_integer(user_id) and user_id > 0 and
             is_integer(target_company_id) and target_company_id > 0 and
             is_list(opts) do
    employee_id = Keyword.get(opts, :employee_id)
    current_session_id = Keyword.get(opts, :current_session_id, "revoke-reassigned-user")

    with :ok <-
           authorize_company_user(
             actor,
             scope,
             current_company_id,
             user_id,
             "admin.user.update"
           ) do
      Repo.transaction(fn ->
        with :ok <- lock_companies_ascending(scope, [current_company_id, target_company_id]),
             {:ok, _emp_proof} <- maybe_lock_employee(scope, target_company_id, employee_id),
             {:ok, user} <- lock_company_user(current_company_id, user_id),
             new_employee_id =
               if(current_company_id == target_company_id,
                 do: employee_id || user.employee_id,
                 else: employee_id
               ),
             {:ok, updated_user} <-
               user
               |> Changeset.change(company_id: target_company_id, employee_id: new_employee_id)
               |> Repo.update(),
             {:ok, _terminated_count} <-
               Session.terminate_user_sessions(user.id, current_session_id),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
                 actor,
                 user.id,
                 "reassigned_company",
                 target_company_id,
                 %{
                   "company_id" => current_company_id,
                   "employee_id" => user.employee_id
                 },
                 %{
                   "company_id" => target_company_id,
                   "employee_id" => new_employee_id
                 }
               ) do
          Summary.from_schema(updated_user)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def reassign_user_company(
        %AuthzActor{},
        %Scope{},
        current_company_id,
        _user_id,
        _target_company_id,
        opts
      )
      when not (is_integer(current_company_id) and current_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  def reassign_user_company(
        %AuthzActor{},
        %Scope{},
        _current_company_id,
        user_id,
        _target_company_id,
        opts
      )
      when not (is_integer(user_id) and user_id > 0) and is_list(opts),
      do: {:error, :user_not_found}

  def reassign_user_company(
        %AuthzActor{},
        %Scope{},
        _current_company_id,
        _user_id,
        target_company_id,
        opts
      )
      when not (is_integer(target_company_id) and target_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  @doc """
  Clears a user's company and employee affiliation, returning them to unaffiliated status.

  Locks the current company and user row, clears `company_id` and `employee_id`,
  terminates existing sessions, and records an atomic audit mutation.
  """
  @spec clear_user_company(
          AuthzActor.t(),
          Scope.t(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :unauthorized | Changeset.t()}
  def clear_user_company(actor, scope, current_company_id, user_id, opts \\ [])

  def clear_user_company(
        %AuthzActor{} = actor,
        %Scope{} = scope,
        current_company_id,
        user_id,
        opts
      )
      when is_integer(current_company_id) and current_company_id > 0 and
             is_integer(user_id) and user_id > 0 and
             is_list(opts) do
    current_session_id = Keyword.get(opts, :current_session_id, "revoke-cleared-company")

    with :ok <-
           authorize_company_user(
             actor,
             scope,
             current_company_id,
             user_id,
             "admin.user.update"
           ) do
      Repo.transaction(fn ->
        with {:ok, _proof} <- lock_target_company(scope, current_company_id),
             {:ok, user} <- lock_company_user(current_company_id, user_id),
             {:ok, updated_user} <-
               user
               |> Changeset.change(company_id: nil, employee_id: nil)
               |> Repo.update(),
             {:ok, _terminated_count} <-
               Session.terminate_user_sessions(user.id, current_session_id),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
                 actor,
                 user.id,
                 "cleared_company",
                 current_company_id,
                 %{
                   "company_id" => current_company_id,
                   "employee_id" => user.employee_id
                 },
                 %{
                   "company_id" => nil,
                   "employee_id" => nil
                 }
               ) do
          Summary.from_schema(updated_user)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def clear_user_company(%AuthzActor{}, %Scope{}, current_company_id, _user_id, opts)
      when not (is_integer(current_company_id) and current_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  def clear_user_company(%AuthzActor{}, %Scope{}, _current_company_id, user_id, opts)
      when not (is_integer(user_id) and user_id > 0) and is_list(opts),
      do: {:error, :user_not_found}

  @doc """
  Replaces a user's password in a trusted administrative workflow without requiring
  the user's existing password.

  Accepts plaintext `:password` only, hashes with Argon2id, rotates `remember_token`,
  terminates active sessions, and writes an atomic audit record without leaking
  credentials.
  """
  @spec admin_change_password(
          AuthzActor.t(),
          Scope.t(),
          pos_integer() | nil,
          pos_integer(),
          String.t(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :unauthorized | :not_platform_operator | Changeset.t()}
  def admin_change_password(actor, scope, company_id, user_id, new_password, opts \\ [])

  def admin_change_password(
        %AuthzActor{} = actor,
        %Scope{} = scope,
        company_id,
        user_id,
        new_password,
        opts
      )
      when (is_nil(company_id) or (is_integer(company_id) and company_id > 0)) and
             is_binary(new_password) and is_integer(user_id) and user_id > 0 and is_list(opts) do
    current_session_id = Keyword.get(opts, :current_session_id, "revoke-admin-password-reset")

    with :ok <- authorize_password_change(actor, scope, company_id, user_id) do
      Repo.transaction(fn ->
        with :ok <- maybe_lock_company(scope, company_id),
             {:ok, user} <- lock_user_for_password_change(company_id, user_id),
             changeset = Schema.password_changeset(user, %{password: new_password}),
             {:ok, updated_user} <- apply_password_reset(user, changeset),
             {:ok, _count} <-
               Session.terminate_user_sessions(user.id, current_session_id),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
                 actor,
                 user.id,
                 "password_reset",
                 company_id,
                 %{},
                 %{"password_changed" => true}
               ) do
          Summary.from_schema(updated_user)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def admin_change_password(%AuthzActor{}, %Scope{}, company_id, _user_id, new_password, opts)
      when not is_nil(company_id) and not (is_integer(company_id) and company_id > 0) and
             is_binary(new_password) and is_list(opts),
      do: {:error, :company_not_found}

  def admin_change_password(%AuthzActor{}, %Scope{}, company_id, user_id, new_password, opts)
      when (is_nil(company_id) or (is_integer(company_id) and company_id > 0)) and
             not (is_integer(user_id) and user_id > 0) and is_binary(new_password) and
             is_list(opts),
      do: {:error, :user_not_found}

  defp record_audit_mutation(scope, actor, user_id, event, company_id, old_values, new_values) do
    Audit.record_mutation(scope, %{
      event: event,
      source: "system",
      occurred_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      auditable_type: notifiable_identity(),
      auditable_id: to_string(user_id),
      actor_type: to_string(actor.type),
      actor_id: actor.id,
      company_id: company_id,
      old_values: old_values,
      new_values: new_values
    })
  end

  @doc """
  The durable polymorphic identity Laravel persists for a user.

  Stored in `notifications.notifiable_type` and, once Authz lands,
  `base_authz_principal_roles.principal_type` companions. It is data, not an
  Elixir module reference: renaming this module must not change the string.
  """
  @spec notifiable_identity() :: String.t()
  def notifiable_identity, do: "App\\Core\\User\\Models\\User"

  defp scoped_user(scope, company_id, user_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, user}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  defp maybe_upgrade_credential(%Schema{password_hash: hash} = user, password) do
    if Password.legacy?(hash) do
      user
      |> Schema.credential_upgrade_changeset(Password.hash(password))
      |> Repo.update()
    else
      {:ok, user}
    end
  end

  defp issue_password_reset(user, deliver_fun) do
    token = random_token()
    changeset = PasswordResetToken.changeset(user.email, Password.hash(token), now())

    changeset
    |> Repo.insert(
      on_conflict: {:replace, [:token, :created_at]},
      conflict_target: [:email]
    )
    |> case do
      {:ok, _reset} -> deliver_password_reset(deliver_fun, Summary.from_schema(user), token)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp deliver_password_reset(deliver_fun, user, token) do
    case deliver_fun.(user, token) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, {:delivery_failed, reason}}

      other ->
        raise ArgumentError,
              "password reset delivery must return :ok or {:error, reason}, got: #{inspect(other)}"
    end
  end

  defp reset_throttled?(email, seconds) do
    cutoff = NaiveDateTime.add(now(), -seconds, :second)

    Repo.exists?(
      from(reset in PasswordResetToken,
        where: reset.email == ^email and reset.created_at > ^cutoff
      )
    )
  end

  defp valid_password_reset(email, token, max_age) do
    user = Repo.get_by(Schema, email: email)
    reset = Repo.get(PasswordResetToken, email)

    if is_nil(user) or is_nil(reset) do
      Password.no_user_verify()
      {:error, :invalid_or_expired_token}
    else
      token_valid? = Password.valid?(token, reset.token)
      cutoff = NaiveDateTime.add(now(), -max_age, :second)
      active? = reset.created_at && NaiveDateTime.compare(reset.created_at, cutoff) != :lt

      if token_valid? and active?,
        do: {:ok, user},
        else: {:error, :invalid_or_expired_token}
    end
  end

  defp preference_scope(scope, company_id, user_id) do
    with {:ok, _user} <- scoped_user(scope, company_id, user_id) do
      {:ok, SettingsScope.user(user_id, company_id, Scope.tenant_id(scope))}
    end
  end

  defp supported_preference(key) do
    if key in @preference_keys, do: :ok, else: {:error, :unsupported_preference}
  end

  defp valid_preference("ui.theme", value) when value in ["light", "dark", "system"], do: :ok

  defp valid_preference("ui.landing_menu_id", value)
       when is_binary(value) and byte_size(value) <= 255, do: :ok

  defp valid_preference(key, value)
       when key in [
              "ui.dashboard.layout",
              "ui.dashboard.sections",
              "ai.last_used_model_hints"
            ] and
              (is_list(value) or is_map(value)),
       do: :ok

  defp valid_preference(_key, _value), do: {:error, :invalid_preference}

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp random_remember_token,
    do: :crypto.strong_rand_bytes(45) |> Base.url_encode64(padding: false)

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp positive_seconds!(seconds, _field) when is_integer(seconds) and seconds > 0, do: seconds

  defp positive_seconds!(_seconds, field) do
    raise ArgumentError, "#{field} must be a positive integer"
  end

  defp non_negative_seconds!(seconds, _field) when is_integer(seconds) and seconds >= 0,
    do: seconds

  defp non_negative_seconds!(_seconds, field) do
    raise ArgumentError, "#{field} must be a non-negative integer"
  end

  # An employee affiliation must belong to the same company as the user.
  # Resolved through Core Employee's public API, never by querying `employees`:
  # that table belongs to another deep module, and `users.employee_id` being a
  # foreign key to it does not grant this module read access to its schema.
  defp validate_employee(%Changeset{valid?: false} = changeset, _scope, _company_id),
    do: changeset

  defp validate_employee(changeset, scope, company_id) do
    case Changeset.get_field(changeset, :employee_id) do
      nil ->
        changeset

      employee_id ->
        case Employee.get_employee(scope, company_id, employee_id) do
          # An agent holds no user account (#581). This policy is the
          # invariant's front door; the employee-page account panel is its
          # reconciliation when an already-linked employee becomes an agent.
          {:ok, %{employee_type: "agent"}} ->
            Changeset.add_error(changeset, :employee_id, "cannot link an account to an agent")

          {:ok, _employee} ->
            changeset

          {:error, _reason} ->
            Changeset.add_error(changeset, :employee_id, "does not belong to the company")
        end
    end
  end

  defp reject_agent_account(_employee, nil), do: :ok
  defp reject_agent_account(%{employee_type: "agent"}, _user_id), do: {:error, :agent_employee}
  defp reject_agent_account(_employee, user_id) when is_integer(user_id) and user_id > 0, do: :ok
  defp reject_agent_account(_employee, _user_id), do: {:error, :user_not_found}

  defp lock_employee_users(company_id, employee_id) do
    users =
      from(user in Schema,
        where: user.company_id == ^company_id and user.employee_id == ^employee_id,
        order_by: [asc: user.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()

    {:ok, users}
  end

  defp lock_replacement_user(_company_id, nil, _employee_id), do: {:ok, nil}

  defp lock_replacement_user(company_id, user_id, employee_id)
       when is_integer(user_id) and user_id > 0 do
    user =
      from(user in Schema,
        where:
          user.id == ^user_id and user.company_id == ^company_id and
            (is_nil(user.employee_id) or user.employee_id == ^employee_id),
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if user, do: {:ok, user}, else: {:error, :user_not_found}
  end

  defp lock_replacement_user(_company_id, _user_id, _employee_id), do: {:error, :user_not_found}

  defp clear_employee_users(linked_users, target_user) do
    linked_users
    |> Enum.reject(&(target_user && &1.id == target_user.id))
    |> Enum.reduce_while(:ok, fn user, :ok ->
      case user |> Schema.update_changeset(%{employee_id: nil}) |> Repo.update() do
        {:ok, _updated} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp attach_employee(nil, _employee_id), do: {:ok, nil}

  defp attach_employee(user, employee_id) do
    case user |> Schema.update_changeset(%{employee_id: employee_id}) |> Repo.update() do
      {:ok, updated} -> {:ok, Summary.from_schema(updated)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_clear_agent_accounts(_linked_users, type) when type != "agent", do: :ok

  defp maybe_clear_agent_accounts(linked_users, "agent"),
    do: clear_employee_users(linked_users, nil)

  defp transaction_result({:ok, result}), do: {:ok, result}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp user_schema(company_id, user_id) do
    Repo.get_by(Schema, id: user_id, company_id: company_id)
  end

  defp persist_insert(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_insert(changeset) do
    case Repo.insert(changeset) do
      {:ok, user} -> {:ok, Summary.from_schema(user)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp persist_update(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_update(changeset) do
    case Repo.update(changeset) do
      {:ok, user} -> {:ok, Summary.from_schema(user)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp verify_platform_operator(scope) do
    if Scope.platform_operator?(scope) do
      :ok
    else
      {:error, :not_platform_operator}
    end
  end

  defp authorize_unaffiliated(actor, scope, user_id \\ nil) do
    if Scope.tenant_id(actor.scope) == Scope.tenant_id(scope) do
      resource_id = if user_id, do: to_string(user_id), else: nil
      resource = Authz.resource("user", resource_id, scope: scope, company_id: nil)

      case Authz.can(actor, "admin.user.unaffiliated.manage", resource) do
        %{allowed: true} -> :ok
        _denied -> {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp authorize_company_user(actor, scope, company_id, user_id, capability) do
    if Scope.tenant_id(actor.scope) == Scope.tenant_id(scope) do
      resource = Authz.resource("user", to_string(user_id), scope: scope, company_id: company_id)

      case Authz.can(actor, capability, resource) do
        %{allowed: true} -> :ok
        _denied -> {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp authorize_password_change(actor, scope, nil, user_id) do
    with :ok <- verify_platform_operator(scope) do
      authorize_unaffiliated(actor, scope, user_id)
    end
  end

  defp authorize_password_change(actor, scope, company_id, user_id) do
    authorize_company_user(actor, scope, company_id, user_id, "admin.user.update")
  end

  defp lock_target_company(scope, company_id) do
    case Company.lock_live_company(scope, company_id) do
      {:ok, proof} -> {:ok, proof}
      {:error, _reason} -> {:error, :company_not_found}
    end
  end

  defp maybe_lock_company(_scope, nil), do: :ok

  defp maybe_lock_company(scope, company_id) do
    case lock_target_company(scope, company_id) do
      {:ok, _proof} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_companies_ascending(scope, company_ids) do
    company_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn cid, :ok ->
      case lock_target_company(scope, cid) do
        {:ok, _proof} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_lock_employee(_scope, _company_id, nil), do: {:ok, nil}

  defp maybe_lock_employee(scope, company_id, employee_id)
       when is_integer(employee_id) and employee_id > 0 do
    case Employee.lock_affiliation(scope, company_id, employee_id) do
      {:ok, proof} -> {:ok, proof}
      {:error, _reason} -> {:error, :employee_not_found}
    end
  end

  defp maybe_lock_employee(_scope, _company_id, _invalid), do: {:error, :employee_not_found}

  defp lock_unaffiliated_user(user_id) do
    user =
      from(u in Schema,
        where: u.id == ^user_id and is_nil(u.company_id) and is_nil(u.employee_id),
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if user, do: {:ok, user}, else: {:error, :user_not_found}
  end

  defp lock_company_user(company_id, user_id) do
    user =
      from(u in Schema,
        where: u.id == ^user_id and u.company_id == ^company_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if user, do: {:ok, user}, else: {:error, :user_not_found}
  end

  defp lock_user_for_password_change(nil, user_id) do
    lock_unaffiliated_user(user_id)
  end

  defp lock_user_for_password_change(company_id, user_id) do
    lock_company_user(company_id, user_id)
  end

  defp apply_password_reset(user, %Changeset{valid?: true} = changeset) do
    password_hash = Changeset.get_change(changeset, :password_hash)
    remember_token = random_remember_token()

    user
    |> Schema.password_reset_changeset(password_hash, remember_token)
    |> Repo.update()
  end

  defp apply_password_reset(_user, %Changeset{} = changeset), do: {:error, changeset}

  defp normalize_company({:ok, company}), do: {:ok, company}
  defp normalize_company({:error, :not_found}), do: {:error, :company_not_found}

  # --- User Database Queries ---

  @doc """
  Lists saved database queries owned by the given user ID within the tenant scope.
  """
  @spec list_database_queries(Scope.t(), pos_integer(), keyword()) ::
          {:ok, [DatabaseQuery.t()]} | {:error, :user_not_found}
  def list_database_queries(%Scope{} = scope, user_id, opts \\ [])
      when is_integer(user_id) and user_id > 0 and is_list(opts) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      search = Keyword.get(opts, :search)
      sort_by = Keyword.get(opts, :sort_by, :name)
      sort_dir = Keyword.get(opts, :sort_dir, :asc)

      base_query = from(q in DatabaseQuery, where: q.user_id == ^user_id)

      query =
        if is_binary(search) and String.trim(search) != "" do
          pattern = "%#{String.trim(search)}%"
          from(q in base_query, where: ilike(q.name, ^pattern) or ilike(q.description, ^pattern))
        else
          base_query
        end

      order_field =
        case sort_by do
          :name -> :name
          :description -> :description
          :created_at -> :created_at
          :updated_at -> :updated_at
          "name" -> :name
          "description" -> :description
          "created_at" -> :created_at
          "updated_at" -> :updated_at
          _ -> :name
        end

      order_expr =
        if sort_dir in [:desc, "desc", "DESC"] do
          [desc: order_field, desc: :id]
        else
          [asc: order_field, asc: :id]
        end

      queries =
        from(q in query, order_by: ^order_expr)
        |> Repo.all()

      {:ok, queries}
    end
  end

  @doc """
  Fetches a database query owned by the user by integer ID or binary slug within the tenant scope.
  """
  @spec get_database_query(Scope.t(), pos_integer(), pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found}
  def get_database_query(%Scope{} = scope, user_id, id)
      when is_integer(user_id) and user_id > 0 and is_integer(id) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      case Repo.get_by(DatabaseQuery, id: id, user_id: user_id) do
        nil -> {:error, :not_found}
        %DatabaseQuery{} = query -> {:ok, query}
      end
    end
  end

  def get_database_query(%Scope{} = scope, user_id, slug)
      when is_integer(user_id) and user_id > 0 and is_binary(slug) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      case Repo.get_by(DatabaseQuery, slug: slug, user_id: user_id) do
        nil -> {:error, :not_found}
        %DatabaseQuery{} = query -> {:ok, query}
      end
    end
  end

  def get_database_query(%Scope{}, _user_id, _invalid), do: {:error, :not_found}

  @doc """
  Creates a new saved database query for the given user ID within the tenant scope.
  """
  @spec create_database_query(Scope.t(), pos_integer(), map()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | Changeset.t()}
  def create_database_query(%Scope{} = scope, user_id, attrs)
      when is_integer(user_id) and user_id > 0 and is_map(attrs) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      user_id
      |> DatabaseQuery.creation_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates an existing database query owned by the user within the tenant scope.
  """
  @spec update_database_query(
          Scope.t(),
          pos_integer(),
          DatabaseQuery.t() | pos_integer() | String.t(),
          map()
        ) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found | Changeset.t()}
  def update_database_query(
        %Scope{} = scope,
        user_id,
        %DatabaseQuery{user_id: user_id} = query,
        attrs
      )
      when is_integer(user_id) and user_id > 0 and is_map(attrs) do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      query
      |> DatabaseQuery.changeset(attrs)
      |> Repo.update()
    end
  end

  def update_database_query(%Scope{} = scope, user_id, id_or_slug, attrs)
      when is_integer(user_id) and user_id > 0 and is_map(attrs) do
    with {:ok, query} <- get_database_query(scope, user_id, id_or_slug) do
      update_database_query(scope, user_id, query, attrs)
    end
  end

  @doc """
  Deletes a saved database query owned by the user within the tenant scope.
  """
  @spec delete_database_query(
          Scope.t(),
          pos_integer(),
          DatabaseQuery.t() | pos_integer() | String.t()
        ) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found | Changeset.t()}
  def delete_database_query(%Scope{} = scope, user_id, %DatabaseQuery{user_id: user_id} = query)
      when is_integer(user_id) and user_id > 0 do
    with {:ok, _user} <- get_tenant_user(scope, user_id) do
      Repo.delete(query)
    end
  end

  def delete_database_query(%Scope{} = scope, user_id, id_or_slug)
      when is_integer(user_id) and user_id > 0 do
    with {:ok, query} <- get_database_query(scope, user_id, id_or_slug) do
      delete_database_query(scope, user_id, query)
    end
  end

  @doc """
  Duplicates an existing database query for the user, assigning a new unique slug.
  """
  @spec duplicate_database_query(
          Scope.t(),
          pos_integer(),
          DatabaseQuery.t() | pos_integer() | String.t()
        ) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found | Changeset.t()}
  def duplicate_database_query(%Scope{} = scope, user_id, id_or_slug)
      when is_integer(user_id) and user_id > 0 do
    with {:ok, original} <- get_database_query(scope, user_id, id_or_slug) do
      attrs = %{
        name: "#{original.name} (Copy)",
        prompt: original.prompt,
        sql_query: original.sql_query,
        description: original.description,
        icon: original.icon
      }

      create_database_query(scope, user_id, attrs)
    end
  end

  @doc """
  Generates a unique slug for a query name scoped to the given user.
  """
  @spec generate_query_slug(pos_integer(), String.t()) :: String.t()
  def generate_query_slug(user_id, name) when is_integer(user_id) and is_binary(name) do
    DatabaseQuery.generate_slug(user_id, name)
  end
end
