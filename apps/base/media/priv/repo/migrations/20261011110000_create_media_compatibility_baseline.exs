defmodule Bilimbi.Base.Media.Migrations.CreateMediaCompatibilityBaseline do
  use Ecto.Migration

  # Current state of Belimbing's three Base Media migrations, including
  # retained_at. Laravel unique() creates table constraints, not bare indexes.
  def change do
    schema = Bilimbi.Base.Database.SchemaVerifier.quote_identifier!(prefix() || "public")

    create table(:base_media_assets, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :parent_id,
          references(:base_media_assets,
            type: :bigint,
            on_delete: :delete_all,
            name: :base_media_assets_parent_id_foreign
          )

      add :disk, :string, null: false
      add :storage_key, :string, null: false
      add :original_filename, :string
      add :mime_type, :string
      add :file_size, :bigint
      add :kind, :string, null: false
      add :metadata, :json
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
    end

    create index(:base_media_assets, [:kind], name: :base_media_assets_kind_index)

    create index(:base_media_assets, [:parent_id, :kind],
             name: :base_media_assets_parent_id_kind_index
           )

    create index(:base_media_assets, [:disk, :storage_key],
             name: :base_media_assets_disk_storage_key_index
           )

    create table(:base_media_attachments, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :public_id, :char, size: 26, null: false

      add :tenant_id,
          references(:tenants,
            type: :bigint,
            on_delete: :delete_all,
            name: :base_media_attachments_tenant_id_foreign
          ),
          null: false

      add :media_asset_id,
          references(:base_media_assets,
            type: :bigint,
            on_delete: :restrict,
            name: :base_media_attachments_media_asset_id_foreign
          ),
          null: false

      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :state, :string, null: false
      add :uploaded_by_type, :string, null: false
      add :uploaded_by_id, :bigint, null: false
      add :submitted_at, :naive_datetime, precision: 0
      add :created_at, :naive_datetime, precision: 0
      add :updated_at, :naive_datetime, precision: 0
      add :retained_at, :naive_datetime, precision: 0
    end

    for field <- [:public_id, :media_asset_id] do
      name = "base_media_attachments_#{field}_unique"

      execute(
        ~s|ALTER TABLE #{schema}."base_media_attachments" ADD CONSTRAINT "#{name}" UNIQUE ("#{field}")|,
        ~s|ALTER TABLE #{schema}."base_media_attachments" DROP CONSTRAINT "#{name}"|
      )
    end

    create index(:base_media_attachments, [:state], name: :base_media_attachments_state_index)

    create index(:base_media_attachments, [:retained_at],
             name: :base_media_attachments_retained_at_index
           )

    create index(:base_media_attachments, [:tenant_id, :subject_type, :subject_id],
             name: :media_attachments_tenant_subject_idx
           )

    create index(:base_media_attachments, [:tenant_id, :state, :created_at],
             name: :media_attachments_draft_cleanup_idx
           )
  end
end
