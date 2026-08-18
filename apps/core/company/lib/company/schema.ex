defmodule Bilimbi.Core.Company.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          parent_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          status: String.t() | nil,
          legal_name: String.t() | nil,
          registration_number: String.t() | nil,
          tax_id: String.t() | nil,
          legal_entity_type_id: pos_integer() | nil,
          jurisdiction: String.t() | nil,
          email: String.t() | nil,
          website: String.t() | nil,
          scope_activities: map() | nil,
          metadata: map() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          deleted_at: NaiveDateTime.t() | nil
        }

  schema "companies" do
    field :parent_id, :id
    field :tenant_id, :id
    field :name, :string
    field :code, :string
    field :status, :string
    field :legal_name, :string
    field :registration_number, :string
    field :tax_id, :string
    field :legal_entity_type_id, :id
    field :jurisdiction, :string
    field :email, :string
    field :website, :string
    field :scope_activities, Bilimbi.Base.Database.Json
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
    field :deleted_at, :naive_datetime
  end

  @creation_fields [
    :parent_id,
    :name,
    :code,
    :status,
    :legal_name,
    :registration_number,
    :tax_id,
    :legal_entity_type_id,
    :jurisdiction,
    :email,
    :website,
    :scope_activities,
    :metadata
  ]

  @spec creation_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(tenant_id, attributes) do
    %__MODULE__{status: "active"}
    |> cast(attributes, @creation_fields)
    |> put_change(:tenant_id, tenant_id)
    |> update_change(:name, &String.trim/1)
    |> update_change(:code, &String.trim/1)
    |> validate_required([:tenant_id, :name, :code, :status])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:code, min: 1, max: 255)
    |> validate_length(:status, min: 1, max: 255)
    |> unique_constraint(:code, name: :companies_code_unique)
    |> foreign_key_constraint(:tenant_id, name: :companies_tenant_foreign)
    |> foreign_key_constraint(:parent_id, name: :companies_parent_tenant_foreign)
  end
end
