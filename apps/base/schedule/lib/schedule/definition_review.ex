defmodule Bilimbi.Base.Schedule.DefinitionReview do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "base_schedule_definition_reviews" do
    field :source, :string
    field :key, :string
    field :fingerprint, :string
    field :enabled, :boolean
    field :reviewed_at, :utc_datetime_usec
  end

  def changeset(review \\ %__MODULE__{}, attributes) do
    review
    |> cast(attributes, [:source, :key, :fingerprint, :enabled, :reviewed_at])
    |> validate_required([:source, :key, :fingerprint, :enabled, :reviewed_at])
    |> unique_constraint([:source, :key],
      name: :base_schedule_definition_reviews_source_key_unique
    )
  end
end
