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
    field(:started_on, :date)
    field(:ended_on, :date)
    field(:legacy_employee_id, :id)
    field(:unlinked_at, :naive_datetime)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(affiliation, attrs) do
    affiliation
    |> cast(attrs, [:title, :email, :phone, :started_on, :ended_on])
    |> validate_required([:tenant_id, :person_id, :company_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
    |> validate_dates()
    |> unique_constraint(:company_id, name: :core_person_affiliations_live_unique)
  end

  defp validate_dates(changeset) do
    started = get_field(changeset, :started_on)
    ended = get_field(changeset, :ended_on)

    if started != nil and ended != nil and Date.compare(started, ended) == :gt,
      do: add_error(changeset, :ended_on, "must be on or after the start date"),
      else: changeset
  end

  @doc """
  The change that ends an affiliation by unlinking it: the end date becomes
  today unless one on or before today is already recorded, and never precedes
  the start date.
  """
  def unlink_changes(%__MODULE__{} = affiliation, today) do
    ended =
      case affiliation.ended_on do
        date when date != nil -> if Date.compare(date, today) == :gt, do: today, else: date
        nil -> today
      end

    ended =
      if affiliation.started_on && Date.compare(affiliation.started_on, ended) == :gt,
        do: affiliation.started_on,
        else: ended

    [ended_on: ended]
  end
end
