defmodule Bilimbi.Core.Person.Relationship do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "core_person_relationships" do
    field(:tenant_id, :id)
    field(:person_id, :id)
    field(:company_id, :id)
    field(:relationship_type_id, :id)
    field(:effective_from, :date)
    field(:effective_to, :date)
    field(:deleted_at, :naive_datetime)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def live_duplicate_message, do: "is already assigned between this company and person"

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:relationship_type_id, :effective_from, :effective_to])
    |> validate_required([:tenant_id, :person_id, :company_id, :relationship_type_id])
    |> validate_effective_dates()
    |> live_unique_constraint(:relationship_type_id)
  end

  def update_changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:effective_from, :effective_to])
    |> validate_effective_dates()
    |> live_unique_constraint(:effective_to)
  end

  defp live_unique_constraint(changeset, field),
    do:
      unique_constraint(changeset, field,
        name: :core_person_relationship_live_unique,
        message: live_duplicate_message()
      )

  defp validate_effective_dates(changeset) do
    from_date = get_field(changeset, :effective_from)
    to_date = get_field(changeset, :effective_to)

    if from_date != nil and to_date != nil and Date.compare(from_date, to_date) == :gt,
      do: add_error(changeset, :effective_to, "must be on or after effective from date"),
      else: changeset
  end
end
