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
    field :password, :string
    field :remember_token, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  # `password` is deliberately absent. This module never accepts a credential
  # through the same cast as ordinary attributes; see put_password_hash/2.
  @fields [:name, :email, :email_verified_at, :employee_id]

  @doc """
  Builds a new user for a company that the caller has already proven.

  `company_id` may be nil: Belimbing's `users.company_id` is nullable, and such
  a user simply belongs to no tenant-scoped list.
  """
  @spec creation_changeset(pos_integer() | nil, map()) :: Ecto.Changeset.t()
  def creation_changeset(company_id, attributes) do
    %__MODULE__{}
    |> cast(attributes, @fields)
    |> put_change(:company_id, company_id)
    |> put_password_hash(attributes)
    |> validate_required([:name, :email, :password])
    |> validate()
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = user, attributes) do
    user
    |> cast(attributes, @fields)
    |> put_password_hash(attributes)
    |> validate_required([:name, :email, :password])
    |> validate()
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

  # This module stores credentials; it never creates them.
  #
  # Belimbing persists Laravel bcrypt output, which is a crypt-format string
  # (`$2y$<cost>$<22-char salt><31-char digest>`). Bilimbi has no hashing
  # dependency yet and S1 deliberately does not add one, so the caller supplies
  # an already-hashed credential under an unambiguous key and anything that is
  # not crypt-format is rejected rather than silently stored as a plaintext
  # password. Registration and verification arrive with authentication in S2.
  @crypt_format ~r/^\$2[aby]\$\d{2}\$[.\/A-Za-z0-9]{53}$/

  defp put_password_hash(changeset, attributes) do
    case fetch_supplied_hash(attributes) do
      :error ->
        changeset

      {:ok, hash} when is_binary(hash) ->
        if Regex.match?(@crypt_format, hash) do
          put_change(changeset, :password, hash)
        else
          add_error(changeset, :password_hash, "must be a bcrypt crypt-format hash")
        end

      {:ok, _other} ->
        add_error(changeset, :password_hash, "must be a bcrypt crypt-format hash")
    end
  end

  defp fetch_supplied_hash(attributes) do
    case Map.fetch(attributes, :password_hash) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attributes, "password_hash")
    end
  end
end
