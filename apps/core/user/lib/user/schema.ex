defmodule Bilimbi.Core.User.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "users" do
    field :company_id, :id
    field :employee_id, :id
    field :name, :string
    field :email, :string
    field :email_verified_at, :naive_datetime
    field :password_hash, :string, source: :password, redact: true
    field :password, :string, virtual: true, redact: true
    field :remember_token, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  @profile_fields [:name, :email, :employee_id]

  @doc """
  Builds a new user for a company that the caller has already proven.

  `company_id` may be nil: Belimbing's `users.company_id` is nullable, and such
  a user simply belongs to no tenant-scoped list.
  """
  @spec creation_changeset(pos_integer() | nil, map(), keyword()) :: Ecto.Changeset.t()
  def creation_changeset(company_id, attributes, opts \\ []) do
    %__MODULE__{}
    |> cast(attributes, @profile_fields ++ [:password])
    |> put_change(:company_id, company_id)
    |> normalize_email_change()
    |> validate_required([:name, :email, :password])
    |> validate_length(:password, min: 8)
    |> validate()
    |> maybe_hash_password(opts)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = user, attributes) do
    user
    |> cast(attributes, @profile_fields)
    |> normalize_email_change()
    |> invalidate_changed_email()
    |> validate_required([:name, :email, :password_hash])
    |> validate()
  end

  @spec password_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def password_changeset(%__MODULE__{} = user, attributes, opts \\ []) do
    user
    |> cast(attributes, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> maybe_hash_password(opts)
  end

  @doc false
  @spec credential_upgrade_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def credential_upgrade_changeset(%__MODULE__{} = user, password_hash) do
    change(user, password_hash: password_hash)
  end

  @doc false
  @spec password_reset_changeset(t(), String.t(), String.t()) :: Ecto.Changeset.t()
  def password_reset_changeset(%__MODULE__{} = user, password_hash, remember_token) do
    change(user, password_hash: password_hash, remember_token: remember_token)
  end

  @doc false
  @spec verify_email_changeset(t(), NaiveDateTime.t()) :: Ecto.Changeset.t()
  def verify_email_changeset(%__MODULE__{} = user, verified_at) do
    change(user, email_verified_at: verified_at)
  end

  @doc false
  @spec normalize_email(String.t()) :: String.t()
  def normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  defp validate(changeset) do
    changeset
    |> validate_length(:name, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be an email address")
    |> unique_constraint(:email, name: :users_email_unique)
    |> foreign_key_constraint(:company_id, name: :users_company_id_foreign)
    |> foreign_key_constraint(:employee_id, name: :users_employee_id_foreign)
  end

  defp normalize_email_change(changeset) do
    update_change(changeset, :email, &normalize_email/1)
  end

  defp invalidate_changed_email(changeset) do
    if get_change(changeset, :email) do
      put_change(changeset, :email_verified_at, nil)
    else
      changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    if changeset.valid? and Keyword.get(opts, :hash_password, true) do
      case get_change(changeset, :password) do
        password when is_binary(password) ->
          changeset
          |> put_change(:password_hash, Bilimbi.Core.User.Password.hash(password))
          |> delete_change(:password)

        _missing ->
          changeset
      end
    else
      changeset
    end
  end
end
