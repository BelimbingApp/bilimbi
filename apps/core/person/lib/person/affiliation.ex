defmodule Bilimbi.Core.Person.Affiliation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "core_person_affiliations" do
    field(:tenant_id, :id)
    field(:person_id, :id)
    field(:company_id, :id)
    field(:title, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:legacy_employee_id, :id)
    field(:unlinked_at, :naive_datetime)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(affiliation, attrs) do
    affiliation
    |> cast(attrs, [:title, :email, :phone])
    |> validate_required([:tenant_id, :person_id, :company_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
    |> unique_constraint(:company_id, name: :core_person_affiliations_live_unique)
  end
end
