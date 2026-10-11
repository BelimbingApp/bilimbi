defmodule Bilimbi.Base.Media.AssetSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  def __audit_auditable_type__, do: "App\\Base\\Media\\Models\\MediaAsset"

  schema "base_media_assets" do
    field :parent_id, :id
    field :disk, :string
    field :storage_key, :string
    field :original_filename, :string
    field :mime_type, :string
    field :file_size, :integer
    field :kind, :string
    # Laravel metadata can be an object or an array. Use the shared compatible
    # JSON type; :map alone cannot load an adopted [] value.
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :parent_id,
      :disk,
      :storage_key,
      :original_filename,
      :mime_type,
      :file_size,
      :kind,
      :metadata
    ])
    |> validate_required([:disk, :storage_key, :kind])
    |> validate_length(:disk, max: 255)
    |> validate_length(:storage_key, max: 255)
    |> validate_length(:kind, max: 255)
    |> validate_length(:original_filename, max: 255)
    |> validate_length(:mime_type, max: 255)
    |> validate_number(:file_size, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:parent_id, name: :base_media_assets_parent_id_foreign)
  end
end
