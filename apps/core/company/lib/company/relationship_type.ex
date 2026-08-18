defmodule Bilimbi.Core.Company.RelationshipType do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          code: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          is_external: boolean(),
          is_active: boolean(),
          metadata: map() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "company_relationship_types" do
    field :code, :string
    field :name, :string
    field :description, :string
    field :is_external, :boolean, default: false
    field :is_active, :boolean, default: true
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
