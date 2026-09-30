defmodule Bilimbi.Base.Artifacts.Schema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "base_artifacts" do
    field(:tenant_id, :integer)
    field(:company_id, :integer)
    field(:owner_id, :string)
    field(:owner_adapter, :string)
    field(:subject, :string)
    field(:kind, :string)
    field(:content_type, :string)
    field(:byte_size, :integer)
    field(:sha256, :string)
    field(:storage_root, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:ready_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:purged_at, :utc_datetime_usec)
    field(:purge_attempts, :integer, default: 0)
    field(:purge_last_error, :string)
    field(:purge_attempted_at, :utc_datetime_usec)
    field(:purge_held_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> validate_required([
      :id,
      :tenant_id,
      :company_id,
      :owner_id,
      :owner_adapter,
      :subject,
      :kind,
      :content_type,
      :byte_size,
      :sha256,
      :storage_root,
      :expires_at
    ])
    |> validate_length(:subject, max: 255)
    |> validate_length(:kind, max: 255)
    |> validate_length(:content_type, max: 255)
    |> validate_length(:owner_id, max: 255)
    |> validate_length(:owner_adapter, max: 255)
    |> validate_number(:company_id, greater_than: 0)
    |> validate_number(:byte_size, greater_than: 0)
    |> check_constraint(:company_id, name: :base_artifacts_company_positive)
    |> foreign_key_constraint(:tenant_id, name: :base_artifacts_tenant_id_fkey)
  end
end
