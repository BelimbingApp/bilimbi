defmodule Bilimbi.Core.Company.RelationshipType do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

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
    field(:code, :string)
    field(:name, :string)
    field(:description, :string)
    field(:is_external, :boolean, default: false)
    field(:is_active, :boolean, default: true)
    field(:inverse_name, :string, virtual: true)
    field(:metadata, Bilimbi.Base.Database.Json)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(type, attrs) do
    type
    |> cast(attrs, [
      :code,
      :name,
      :description,
      :is_external,
      :is_active,
      :metadata,
      :inverse_name
    ])
    |> store_inverse()
    |> validate_inverse()
    |> validate_required([:code, :name])
    |> validate_length(:code, max: 255)
    |> validate_length(:name, max: 255)
    |> unique_constraint(:code, name: :company_relationship_types_code_unique)
  end

  def update_changeset(type, attrs), do: changeset(type, Map.drop(attrs, [:code, "code"]))

  defp validate_inverse(cs) do
    # Legacy catalogue rows have no inverse metadata and keep their IDs. New
    # custom roles must supply both perspectives instead of inventing symmetry.
    if is_nil(cs.data.id) and is_nil(metadata_inverse(get_field(cs, :metadata))),
      do: add_error(cs, :inverse_name, "is required"),
      else: cs
  end

  defp store_inverse(cs) do
    case fetch_change(cs, :inverse_name) do
      {:ok, value} when is_binary(value) and value != "" ->
        case get_field(cs, :metadata) do
          nil ->
            put_change(cs, :metadata, %{"inverse_name" => value})

          metadata when is_map(metadata) ->
            put_change(cs, :metadata, Map.put(metadata, "inverse_name", value))

          _ ->
            add_error(
              cs,
              :inverse_name,
              "cannot change inverse while legacy metadata is not an object"
            )
        end

      _ ->
        cs
    end
  end

  def inverse_name(type), do: metadata_inverse(type.metadata) || "Source of #{type.name}"
  defp metadata_inverse(metadata) when is_map(metadata), do: Map.get(metadata, "inverse_name")
  defp metadata_inverse(_), do: nil
end
