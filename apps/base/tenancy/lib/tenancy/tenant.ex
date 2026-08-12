defmodule Bilimbi.Base.Tenancy.Tenant do
  @moduledoc """
  Tenant data owned by Base Tenancy.

  A tenant is the outer data-isolation boundary. Base intentionally exposes no
  Company association because Company belongs to Core.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "tenants" do
    field :parent_id, :id
    field :name, :string
    field :status, :string, default: "active"
    field :is_platform_operator, :boolean, default: false
    timestamps(type: :naive_datetime, inserted_at: :created_at)
    field :deleted_at, :naive_datetime
  end

  @spec creation_changeset(map()) :: Ecto.Changeset.t()
  def creation_changeset(attributes) do
    %__MODULE__{}
    |> cast(attributes, [:parent_id, :name, :status])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :status])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:status, min: 1, max: 255)
  end

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          parent_id: pos_integer() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          is_platform_operator: boolean(),
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          deleted_at: NaiveDateTime.t() | nil
        }
end
