defmodule Bilimbi.Core.Company.ExternalAccess do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @fields [
    :relationship_id,
    :user_id,
    :permissions,
    :is_active,
    :access_granted_at,
    :access_expires_at,
    :metadata
  ]

  schema "company_external_accesses" do
    field :company_id, :id
    field :relationship_id, :id
    field :user_id, :id
    field :permissions, Bilimbi.Base.Database.Json
    field :is_active, :boolean, default: true
    field :access_granted_at, :naive_datetime
    field :access_expires_at, :naive_datetime
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
    field :deleted_at, :naive_datetime
  end

  @spec creation_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(company_id, attributes) do
    %__MODULE__{is_active: true}
    |> cast(attributes, @fields)
    |> put_change(:company_id, company_id)
    |> validate_required([:company_id, :relationship_id, :is_active])
    |> validate_period()
    |> foreign_key_constraint(:company_id, name: :company_external_accesses_company_id_foreign)
    |> foreign_key_constraint(:relationship_id,
      name: :company_external_accesses_relationship_id_foreign
    )
    |> foreign_key_constraint(:user_id, name: :company_external_accesses_user_id_foreign)
  end

  @spec update_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def update_changeset(access, attributes) do
    access
    |> cast(attributes, @fields)
    |> validate_required([:company_id, :relationship_id, :is_active])
    |> validate_period()
    |> foreign_key_constraint(:relationship_id,
      name: :company_external_accesses_relationship_id_foreign
    )
    |> foreign_key_constraint(:user_id, name: :company_external_accesses_user_id_foreign)
  end

  defp validate_period(changeset) do
    granted = get_field(changeset, :access_granted_at)
    expires = get_field(changeset, :access_expires_at)

    if granted && expires && NaiveDateTime.compare(expires, granted) == :lt do
      add_error(changeset, :access_expires_at, "must be on or after access granted at")
    else
      changeset
    end
  end
end
