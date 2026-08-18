defmodule Bilimbi.Core.Company.Relationship do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          company_id: pos_integer() | nil,
          related_company_id: pos_integer() | nil,
          relationship_type_id: pos_integer() | nil,
          effective_from: Date.t() | nil,
          effective_to: Date.t() | nil,
          metadata: map() | nil,
          deleted_at: NaiveDateTime.t() | nil,
          company: Bilimbi.Core.Company.Schema.t() | Ecto.Association.NotLoaded.t() | nil,
          related_company: Bilimbi.Core.Company.Schema.t() | Ecto.Association.NotLoaded.t() | nil,
          type: Bilimbi.Core.Company.RelationshipType.t() | Ecto.Association.NotLoaded.t() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "company_relationships" do
    field :effective_from, :date
    field :effective_to, :date
    field :metadata, Bilimbi.Base.Database.Json
    field :deleted_at, :naive_datetime

    belongs_to :company, Bilimbi.Core.Company.Schema, foreign_key: :company_id
    belongs_to :related_company, Bilimbi.Core.Company.Schema, foreign_key: :related_company_id
    belongs_to :type, Bilimbi.Core.Company.RelationshipType, foreign_key: :relationship_type_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :company_id,
      :related_company_id,
      :relationship_type_id,
      :effective_from,
      :effective_to,
      :metadata
    ])
    |> validate_required([:company_id, :related_company_id, :relationship_type_id])
    |> validate_not_same_company()
    |> validate_effective_dates()
    |> unique_constraint(
      [:company_id, :related_company_id, :relationship_type_id, :effective_from],
      name: :company_relationship_unique
    )
    |> foreign_key_constraint(:company_id, name: :company_relationships_company_id_foreign)
    |> foreign_key_constraint(:related_company_id,
      name: :company_relationships_related_company_id_foreign
    )
    |> foreign_key_constraint(:relationship_type_id,
      name: :company_relationships_relationship_type_id_foreign
    )
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:effective_from, :effective_to, :metadata])
    |> validate_effective_dates()
  end

  defp validate_not_same_company(changeset) do
    company_id = get_field(changeset, :company_id)
    related_company_id = get_field(changeset, :related_company_id)

    if company_id != nil and company_id == related_company_id do
      add_error(changeset, :related_company_id, "cannot create a relationship with itself")
    else
      changeset
    end
  end

  defp validate_effective_dates(changeset) do
    from_date = get_field(changeset, :effective_from)
    to_date = get_field(changeset, :effective_to)

    if from_date != nil and to_date != nil and Date.compare(from_date, to_date) == :gt do
      add_error(changeset, :effective_to, "must be on or after effective from date")
    else
      changeset
    end
  end

  @spec active?(t(), Date.t()) :: boolean()
  def active?(%__MODULE__{} = relationship, today \\ Date.utc_today()) do
    from_ok? =
      is_nil(relationship.effective_from) or
        Date.compare(relationship.effective_from, today) in [:lt, :eq]

    to_ok? =
      is_nil(relationship.effective_to) or
        Date.compare(relationship.effective_to, today) in [:gt, :eq]

    is_nil(relationship.deleted_at) and from_ok? and to_ok?
  end
end
