defmodule Bilimbi.Base.Media.AttachmentSchema do
  @moduledoc false
  use Ecto.Schema

  def __audit_auditable_type__, do: "App\\Base\\Media\\Models\\MediaAttachment"

  schema "base_media_attachments" do
    field :public_id, :string
    field :tenant_id, :id
    field :media_asset_id, :id
    field :subject_type, :string
    field :subject_id, :string
    field :state, :string
    field :uploaded_by_type, :string
    field :uploaded_by_id, :integer
    field :submitted_at, :naive_datetime
    field :retained_at, :naive_datetime
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
