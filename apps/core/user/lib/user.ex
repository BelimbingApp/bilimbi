defmodule Bilimbi.Core.User do
  @moduledoc """
  Public API for user accounts, credentials, and user-owned preferences.

  Sidebar pins, in-app notifications, and saved database queries are implemented
  in `Bilimbi.Core.User.Pins`, `Bilimbi.Core.User.Notifications`, and
  `Bilimbi.Core.User.DatabaseQueries`. This module delegates those public
  functions and keeps the names callers already use.

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
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.DatabaseQueries
  alias Bilimbi.Core.User.DatabaseQuery
  alias Bilimbi.Core.User.EmailVerification
  alias Bilimbi.Core.User.Notification
  alias Bilimbi.Core.User.Notifications
  alias Bilimbi.Core.User.Password
  alias Bilimbi.Core.User.PasswordResetToken
  alias Bilimbi.Core.User.Pin
  alias Bilimbi.Core.User.Pins
  alias Bilimbi.Core.User.Schema
  alias Bilimbi.Core.User.Summary
  alias Ecto.Changeset

  @type lookup_error ::
          :company_not_found
          | :user_not_found
          | :employee_not_found
          | :unauthorized
  @type credential_error :: :invalid_credentials | :credential_upgrade_failed

  @doc """
  Provisions the explicitly selected initial platform administrator once.

  This trusted installation API accepts atom-keyed `:tenant_name`,
  `:company_name`, `:company_code`, `:admin_name`, `:admin_email`, and
  `:password`. Optional `:legal_name`, `:jurisdiction` and `:metadata` initialize
  the company profile only on first provisioning. It refuses any pre-existing
  account or platform operator
  without its own completed receipt; adopted installations use their existing
  administrators. System roles must already have been seeded.

  Creation, role assignment, receipt, and retained console audit action commit
  together. Concurrent calls serialize against account creation. Matching
  repeats return `:already_completed` without changing passwords, names or
  grants, including revoked grants. Different installation identities fail.
  Password is required only for first provisioning. Never expose this API as
  an HTTP route. Release and development setup are the trusted callers.
  """
  @spec bootstrap_platform_admin(map()) ::
          {:ok, :created | :already_completed} | {:error, atom()}
  defdelegate bootstrap_platform_admin(attributes), to: Bilimbi.Core.User.AdminBootstrap, as: :run

  @preference_keys [
    "ai.last_used_model_hints",
    "ui.dashboard.layout",
    "ui.dashboard.sections",
    "ui.landing_menu_id",
    "ui.theme"
  ]

  @password_reset_max_age 3_600
  @password_reset_throttle 60

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

  @doc """
  Tenant-wide dashboard counts and the first five accounts ordered by ID.

  Uses the same company visibility as `list_users/1`, including archived
  companies. Counts and the bounded preview share one database snapshot;
  credentials are not selected and only five account records leave the query.
  """
  @spec dashboard_summary(Scope.t()) ::
          {:ok,
           %{
             total: non_neg_integer(),
             verified: non_neg_integer(),
             unverified: non_neg_integer(),
             users: [Summary.t()]
           }}
  def dashboard_summary(%Scope{} = scope) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    rows =
      from(user in Schema,
        where: user.company_id in ^company_ids,
        windows: [all_users: []],
        order_by: user.id,
        limit: 5,
        select: {
          struct(user, [
            :id,
            :company_id,
            :employee_id,
            :name,
            :email,
            :email_verified_at,
            :created_at,
            :updated_at
          ]),
          over(count(user.id), :all_users),
          over(filter(count(user.id), not is_nil(user.email_verified_at)), :all_users)
        }
      )
      |> Repo.all()

    case rows do
      [] ->
        {:ok, %{total: 0, verified: 0, unverified: 0, users: []}}

      [{_, total, verified} | _] ->
        users = Enum.map(rows, fn {user, _, _} -> Summary.from_schema(user) end)
        {:ok, %{total: total, verified: verified, unverified: total - verified, users: users}}
    end
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
  @spec update_password(Scope.t(), pos_integer(), pos_integer(), String.t(), String.t()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | :invalid_password | Changeset.t()}
  def update_password(%Scope{} = scope, company_id, user_id, current_password, new_password)
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

  @doc "Returns the module-owned preferences of the signed-in user."
  @spec user_preferences(Scope.t()) ::
          {:ok, %{required(String.t()) => term()}} | {:error, lookup_error()}
  def user_preferences(%Scope{} = scope) do
    with {:ok, user_id, company_id} <- acting_user(scope),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      {:ok, Settings.get_many(@preference_keys, settings_scope)}
    end
  end

  @doc "Reads one module-owned preference of the signed-in user."
  @spec get_user_preference(Scope.t(), String.t()) ::
          {:ok, term()} | {:error, lookup_error() | :unsupported_preference}
  def get_user_preference(%Scope{} = scope, key) when is_binary(key) do
    with {:ok, user_id, company_id} <- acting_user(scope),
         :ok <- supported_preference(key),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      {:ok, Settings.get(key, settings_scope)}
    end
  end

  @doc "Stores one validated module-owned preference of the signed-in user."
  @spec put_user_preference(Scope.t(), String.t(), term()) ::
          {:ok, term()}
          | {:error,
             lookup_error() | :unsupported_preference | :invalid_preference | Changeset.t()}
  def put_user_preference(%Scope{} = scope, key, value) when is_binary(key) do
    with {:ok, user_id, company_id} <- acting_user(scope),
         :ok <- supported_preference(key),
         :ok <- valid_preference(key, value),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      Settings.put(key, value, settings_scope)
    end
  end

  @doc "Deletes one user override so the module-owned default resolves again."
  @spec delete_user_preference(Scope.t(), String.t()) ::
          :ok | {:error, lookup_error() | :unsupported_preference}
  def delete_user_preference(%Scope{} = scope, key) when is_binary(key) do
    with {:ok, user_id, company_id} <- acting_user(scope),
         :ok <- supported_preference(key),
         {:ok, settings_scope} <- preference_scope(scope, company_id, user_id) do
      Settings.delete(key, settings_scope)
    end
  end

  @doc "Lists pinned items for the signed-in user, ordered by sort_order."
  @spec list_user_pins(Scope.t()) :: {:ok, [Pin.t()]} | {:error, :unauthorized}
  defdelegate list_user_pins(scope), to: Pins

  @doc """
  Toggles a pinned item for the signed-in user.

  If a pin with the same normalized URL already exists, it is deleted.
  Otherwise, a new pin is appended with the next sort_order value.
  Impersonation and a system actor are refused.
  Returns `{:ok, :pinned | :unpinned, [Pin.t()]}` or
  `{:error, Changeset.t() | :unauthorized | :impersonating}`.
  """
  @spec toggle_user_pin(Scope.t(), map()) ::
          {:ok, :pinned | :unpinned, [Pin.t()]}
          | {:error, Changeset.t() | :unauthorized | :impersonating}
  defdelegate toggle_user_pin(scope, attrs), to: Pins

  @doc """
  Reorders the signed-in user's pinned items to match `ordered_pin_ids`.
  Impersonation and a system actor are refused.
  Returns `{:ok, [Pin.t()]}` or `{:error, :unauthorized | :impersonating}`.
  """
  @spec reorder_user_pins(Scope.t(), [pos_integer()]) ::
          {:ok, [Pin.t()]} | {:error, :unauthorized | :impersonating}
  defdelegate reorder_user_pins(scope, ordered_pin_ids), to: Pins

  @doc "Topic name for PubSub notification events per tenant and user."
  @spec notification_topic(pos_integer(), pos_integer()) :: String.t()
  defdelegate notification_topic(tenant_id, user_id), to: Notifications

  @doc "Subscribes the calling process to notifications for the given user in tenant scope."
  @spec subscribe_notifications(Scope.t(), pos_integer()) :: :ok | {:error, :pubsub_unavailable}
  defdelegate subscribe_notifications(scope, user_id), to: Notifications

  @doc """
  Broadcasts a notification change event to subscribers.

  A configured unavailable PubSub transport returns a bounded error and emits a
  redacted telemetry event. Notification mutations that have already committed
  preserve their successful result when that delivery fails.
  """
  @spec broadcast_notification(Scope.t(), pos_integer(), term()) ::
          :ok | {:error, :pubsub_unavailable}
  defdelegate broadcast_notification(scope, user_id, event), to: Notifications

  @doc """
  Sends an in-app database notification to a user within tenant scope.
  `attrs` can be a map with `:title`, `:body`, `:url`, `:icon`, `:type`, `:data`, etc.
  """
  @spec send_notification(Scope.t(), pos_integer(), map()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | Changeset.t()}
  defdelegate send_notification(scope, user_id, attrs), to: Notifications

  @doc """
  Lists notifications for the signed-in user, ordered by creation descending.
  Options:
    - `:status` - `:all` (default), `:unread`, or `:read`
    - `:page` - positive integer (default nil)
    - `:per_page` - positive integer (default 25)
    - `:limit` - positive integer or nil (default nil)
    - `:offset` - non-negative integer (default 0)
  """
  @spec list_notifications(Scope.t(), keyword()) ::
          {:ok, [Notification.t()]} | {:error, :user_not_found | :unauthorized}
  defdelegate list_notifications(scope, opts), to: Notifications

  def list_notifications(scope), do: list_notifications(scope, [])

  @doc """
  Counts notifications for the signed-in user under the given status.
  """
  @spec count_notifications(Scope.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  defdelegate count_notifications(scope, opts), to: Notifications

  def count_notifications(scope), do: count_notifications(scope, [])

  @doc "Returns the count of unread notifications for the signed-in user."
  @spec unread_notification_count(Scope.t()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  defdelegate unread_notification_count(scope), to: Notifications

  @doc "Gets a notification by UUID for the signed-in user."
  @spec get_notification(Scope.t(), binary()) ::
          {:ok, Notification.t()} | {:error, :user_not_found | :not_found | :unauthorized}
  defdelegate get_notification(scope, notification_id), to: Notifications

  @doc "Marks a specific notification as read for the signed-in user."
  @spec mark_notification_as_read(Scope.t(), binary()) ::
          {:ok, Notification.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  defdelegate mark_notification_as_read(scope, notification_id), to: Notifications

  @doc "Marks all unread notifications as read for the signed-in user."
  @spec mark_all_notifications_as_read(Scope.t()) ::
          {:ok, non_neg_integer()} | {:error, :user_not_found | :unauthorized}
  defdelegate mark_all_notifications_as_read(scope), to: Notifications

  @doc "Deletes a notification for the signed-in user."
  @spec delete_notification(Scope.t(), binary()) ::
          {:ok, Notification.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  defdelegate delete_notification(scope, notification_id), to: Notifications

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
          | {:error, lookup_error() | :employee_not_found | :invariant_violation | Changeset.t()}
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
  @spec update_employee_type(Scope.t(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, Bilimbi.Core.Employee.Summary.t()}
          | {:error, lookup_error() | :employee_not_found | :invariant_violation | Changeset.t()}
  def update_employee_type(%Scope{} = scope, company_id, employee_id, type)
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

  @doc """
  Deletes one user in the scope's company.

  Requires `admin.user.delete` now. The user screen's delete control only
  shows the action. An anonymous system actor (tests and `Tenancy.scope/1`)
  is allowed; a person and a named system principal are decided by Authz.
  """
  @spec delete_user(Scope.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, lookup_error() | :forbidden}
  def delete_user(%Scope{} = scope, company_id, user_id) do
    with :ok <- authorize_delete(scope),
         {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, _} = Repo.delete(user)
      :ok
    else
      {:error, :forbidden} = error -> error
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  defp authorize_delete(%Scope{} = scope) do
    actor = Scope.actor(scope)

    if TenancyActor.system?(actor) and is_nil(TenancyActor.system_principal(actor)) do
      :ok
    else
      case Authz.can(scope, "admin.user.delete") do
        %{allowed: true} -> :ok
        %{allowed: false} -> {:error, :forbidden}
      end
    end
  end

  @doc """
  Reassigns a user from one live company to another within the proven tenant scope.

  Locks both companies in ascending ID order before taking the User row lock.
  If an `employee_id` is passed, validates and locks it against the target company;
  otherwise clears the employee link so no cross-company employee association remains.
  Terminates existing sessions and records an atomic audit mutation.
  """
  @spec reassign_user_company(
          Scope.t(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :employee_not_found | :unauthorized | Changeset.t()}
  def reassign_user_company(
        scope,
        current_company_id,
        user_id,
        target_company_id,
        opts \\ []
      )

  def reassign_user_company(
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
        %Scope{},
        current_company_id,
        _user_id,
        _target_company_id,
        opts
      )
      when not (is_integer(current_company_id) and current_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  def reassign_user_company(
        %Scope{},
        _current_company_id,
        user_id,
        _target_company_id,
        opts
      )
      when not (is_integer(user_id) and user_id > 0) and is_list(opts),
      do: {:error, :user_not_found}

  def reassign_user_company(
        %Scope{},
        _current_company_id,
        _user_id,
        target_company_id,
        opts
      )
      when not (is_integer(target_company_id) and target_company_id > 0) and is_list(opts),
      do: {:error, :company_not_found}

  @doc """
  Replaces a user's password in a trusted administrative workflow without requiring
  the user's existing password.

  Accepts plaintext `:password` only, hashes with Argon2id, rotates `remember_token`,
  terminates active sessions, and writes an atomic audit record without leaking
  credentials.
  """
  @spec admin_change_password(
          Scope.t(),
          pos_integer(),
          pos_integer(),
          String.t(),
          keyword()
        ) ::
          {:ok, Summary.t()}
          | {:error, lookup_error() | :unauthorized | Changeset.t()}
  def admin_change_password(scope, company_id, user_id, new_password, opts \\ [])

  def admin_change_password(
        %Scope{} = scope,
        company_id,
        user_id,
        new_password,
        opts
      )
      when is_integer(company_id) and company_id > 0 and is_binary(new_password) and
             is_integer(user_id) and user_id > 0 and is_list(opts) do
    current_session_id = Keyword.get(opts, :current_session_id, "revoke-admin-password-reset")

    with :ok <- authorize_password_change(scope, company_id, user_id) do
      Repo.transaction(fn ->
        with {:ok, _proof} <- lock_target_company(scope, company_id),
             {:ok, user} <- lock_company_user(company_id, user_id),
             changeset = Schema.password_changeset(user, %{password: new_password}),
             {:ok, updated_user} <- apply_password_reset(user, changeset),
             {:ok, _count} <-
               Session.terminate_user_sessions(user.id, current_session_id),
             {:ok, _mutation} <-
               record_audit_mutation(
                 scope,
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

  def admin_change_password(%Scope{}, company_id, _user_id, new_password, opts)
      when not (is_integer(company_id) and company_id > 0) and is_binary(new_password) and
             is_list(opts),
      do: {:error, :company_not_found}

  def admin_change_password(%Scope{}, company_id, user_id, new_password, opts)
      when is_integer(company_id) and company_id > 0 and
             not (is_integer(user_id) and user_id > 0) and is_binary(new_password) and
             is_list(opts),
      do: {:error, :user_not_found}

  # Called only after `authorize_company_user/4` allowed the scope's user.
  defp record_audit_mutation(scope, user_id, event, company_id, old_values, new_values) do
    %TenancyActor{type: :user, user_id: actor_id} = Scope.actor(scope)

    Audit.record_mutation(scope, %{
      event: event,
      source: "system",
      occurred_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      auditable_type: notifiable_identity(),
      auditable_id: to_string(user_id),
      actor_type: "user",
      actor_id: actor_id,
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

  defp acting_user(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id, company_id: company_id}
      when is_integer(user_id) and user_id > 0 and is_integer(company_id) and company_id > 0 ->
        {:ok, user_id, company_id}

      %TenancyActor{} ->
        {:error, :unauthorized}
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

  # The account's company need not be the one the administrator signed in at,
  # so the grant is judged in the account's company.
  defp authorize_company_user(%Scope{} = scope, company_id, user_id, capability) do
    resource = Authz.resource("user", to_string(user_id), scope: scope, company_id: company_id)

    case Authz.can_in_company(scope, company_id, capability, resource) do
      %{allowed: true} -> :ok
      _denied -> {:error, :unauthorized}
    end
  end

  defp authorize_password_change(scope, company_id, user_id) do
    authorize_company_user(scope, company_id, user_id, "admin.user.update")
  end

  defp lock_target_company(scope, company_id) do
    case Company.lock_live_company(scope, company_id) do
      {:ok, proof} -> {:ok, proof}
      {:error, _reason} -> {:error, :company_not_found}
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
    # The protected platform orchestrator is refused as an invariant, not
    # hidden as a missing record; every other failure collapses to not found.
    case Employee.lock_affiliation(scope, company_id, employee_id) do
      {:ok, proof} -> {:ok, proof}
      {:error, :invariant_violation} = error -> error
      {:error, _reason} -> {:error, :employee_not_found}
    end
  end

  defp maybe_lock_employee(_scope, _company_id, _invalid), do: {:error, :employee_not_found}

  defp lock_company_user(company_id, user_id) do
    user =
      from(u in Schema,
        where: u.id == ^user_id and u.company_id == ^company_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if user, do: {:ok, user}, else: {:error, :user_not_found}
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

  @doc """
  Lists saved database queries owned by the signed-in user.
  """
  @spec list_database_queries(Scope.t(), keyword()) ::
          {:ok, [DatabaseQuery.t()]} | {:error, :user_not_found | :unauthorized}
  defdelegate list_database_queries(scope, opts), to: DatabaseQueries

  def list_database_queries(scope), do: list_database_queries(scope, [])

  @doc """
  Fetches a database query owned by the user by integer ID or binary slug within the tenant scope.
  """
  @spec get_database_query(Scope.t(), pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :not_found | :unauthorized}
  defdelegate get_database_query(scope, id_or_slug), to: DatabaseQueries

  @doc """
  Creates a saved database query for the signed-in user.
  """
  @spec create_database_query(Scope.t(), map()) ::
          {:ok, DatabaseQuery.t()} | {:error, :user_not_found | :unauthorized | Changeset.t()}
  defdelegate create_database_query(scope, attrs), to: DatabaseQueries

  @doc """
  Updates an existing database query owned by the user within the tenant scope.
  """
  @spec update_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t(), map()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  defdelegate update_database_query(scope, id_or_slug, attrs), to: DatabaseQueries

  @doc """
  Deletes a saved database query owned by the user within the tenant scope.
  """
  @spec delete_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  defdelegate delete_database_query(scope, id_or_slug), to: DatabaseQueries

  @doc """
  Duplicates an existing database query for the user, assigning a new unique slug.
  """
  @spec duplicate_database_query(Scope.t(), DatabaseQuery.t() | pos_integer() | String.t()) ::
          {:ok, DatabaseQuery.t()}
          | {:error, :user_not_found | :not_found | :unauthorized | Changeset.t()}
  defdelegate duplicate_database_query(scope, id_or_slug), to: DatabaseQueries

  @doc """
  Generates a unique slug for a query name scoped to the signed-in user.
  """
  @spec generate_query_slug(Scope.t(), String.t()) :: {:ok, String.t()} | {:error, :unauthorized}
  defdelegate generate_query_slug(scope, name), to: DatabaseQueries
end
