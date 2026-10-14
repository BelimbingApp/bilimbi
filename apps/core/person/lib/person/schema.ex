defmodule Bilimbi.Core.Person.Schema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "core_people" do
    field(:tenant_id, :id)
    field(:full_name, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:retired_at, :naive_datetime)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:full_name, :email, :phone])
    |> trim()
    |> validate_required([:tenant_id, :full_name])
    |> validate_length(:full_name, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
  end

  defp trim(changeset) do
    Enum.reduce([:full_name, :email, :phone], changeset, fn field, acc ->
      update_change(acc, field, fn
        nil -> nil
        value -> String.trim(value)
      end)
    end)
  end
end
