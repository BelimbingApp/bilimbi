defmodule Bilimbi.Core.Company.DepartmentType do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @categories ~w(administrative operational revenue support)

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          code: String.t() | nil,
          name: String.t() | nil,
          category: String.t(),
          description: String.t() | nil,
          is_active: boolean(),
          metadata: map() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "company_department_types" do
    field :code, :string
    field :name, :string
    field :category, :string, default: "operational"
    field :description, :string
    field :is_active, :boolean, default: true
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def categories, do: @categories

  @fields [:code, :name, :category, :description, :is_active, :metadata]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(type, attrs) do
    type
    |> cast(attrs, @fields)
    |> update_change(:code, &String.trim/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:code, :name, :category])
    |> validate_length(:code, min: 1, max: 255)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:category, @categories)
    |> unique_constraint(:code, name: :company_department_types_code_unique)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(type, attrs) do
    type
    |> cast(attrs, [:name, :category, :description, :is_active, :metadata])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :category])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:category, @categories)
  end
end
