defmodule Bilimbi.Base.Artifacts.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:base_artifacts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:tenant_id, references(:tenants, type: :bigint, on_delete: :restrict), null: false)
      # Base cannot depend upward on Core Company. The trusted owner validates
      # company identity through its public API on every operation.
      add(:company_id, :bigint, null: false)
      add(:owner_id, :string, null: false)
      add(:owner_adapter, :string, null: false)
      add(:subject, :string, null: false)
      add(:kind, :string, null: false)
      add(:content_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      add(:sha256, :string, size: 64, null: false)
      add(:storage_root, :text, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:ready_at, :utc_datetime_usec)
      add(:deleted_at, :utc_datetime_usec)
      add(:purged_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(constraint(:base_artifacts, :base_artifacts_company_positive, check: "company_id > 0"))
    create(constraint(:base_artifacts, :base_artifacts_bytes_positive, check: "byte_size > 0"))

    create(
      index(:base_artifacts, [:tenant_id, :company_id, :owner_id, :expires_at],
        name: :base_artifacts_retention_index
      )
    )
  end
end
