defmodule Bilimbi.Base.Settings.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @key_max_length 255

  @doc """
  The stored key limit, shared so the definition validator can reject an
  over-long key where every other malformed definition is rejected.

  Written once: a migration widening the column should not depend on anyone
  remembering a second file.
  """
  @spec key_max_length() :: pos_integer()
  def key_max_length, do: @key_max_length

  schema "base_settings" do
    field(:key, :string)
    field(:value, Bilimbi.Base.Settings.JsonValue)
    field(:is_encrypted, :boolean, default: false)
    field(:scope_type, :string)
    field(:scope_id, :id)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schema \\ %__MODULE__{}, attributes) do
    schema
    |> cast(attributes, [:key, :value, :is_encrypted, :scope_type, :scope_id])
    |> validate_required([:key, :is_encrypted])
    |> validate_change(:value, fn
      :value, nil -> [value: "cannot be nil"]
      :value, _value -> []
    end)
    |> validate_length(:key, max: @key_max_length)
    |> validate_length(:scope_type, max: 50)
    |> validate_inclusion(:scope_type, ["company", "tenant", "user"])
    |> validate_scope_pair()
    |> unique_constraint(:key, name: :base_settings_key_scope_unique)
    |> unique_constraint(:key, name: :base_settings_global_key_unique)
  end

  @type t :: %__MODULE__{}

  defp validate_scope_pair(changeset) do
    scope_type = get_field(changeset, :scope_type)
    scope_id = get_field(changeset, :scope_id)

    if (is_nil(scope_type) and is_nil(scope_id)) or
         (is_binary(scope_type) and is_integer(scope_id) and scope_id > 0) do
      changeset
    else
      add_error(changeset, :scope_id, "must be present exactly when scope_type is present")
    end
  end
end
