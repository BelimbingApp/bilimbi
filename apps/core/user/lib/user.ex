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

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.EmailVerification
  alias Bilimbi.Core.User.Password
  alias Bilimbi.Core.User.PasswordResetToken
  alias Bilimbi.Core.User.Schema
  alias Bilimbi.Core.User.Summary
  alias Ecto.Changeset

  @type lookup_error :: :company_not_found | :user_not_found
  @type credential_error :: :invalid_credentials | :credential_upgrade_failed

  @preference_keys [
    "ai.last_used_model_hints",
    "ui.dashboard.layout",
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

  @doc "Returns the four module-owned preferences resolved at user scope."
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
       when key in ["ui.dashboard.layout", "ai.last_used_model_hints"] and
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
          {:ok, _employee} ->
            changeset

          {:error, _reason} ->
            Changeset.add_error(changeset, :employee_id, "does not belong to the company")
        end
    end
  end

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

  defp normalize_company({:ok, company}), do: {:ok, company}
  defp normalize_company({:error, :not_found}), do: {:error, :company_not_found}
end
