defmodule Bilimbi.Base.Settings.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:base_settings, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:key, :string, null: false)
      add(:value, :json, null: false)
      add(:is_encrypted, :boolean, null: false, default: false)
      add(:scope_type, :string, size: 50)
      add(:scope_id, :bigint)
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create(
      unique_index(:base_settings, [:key, :scope_type, :scope_id],
        name: :base_settings_key_scope_unique
      )
    )

    create(index(:base_settings, [:scope_type, :scope_id]))

    create(
      unique_index(:base_settings, [:key],
        name: :base_settings_global_key_unique,
        where: "scope_type IS NULL AND scope_id IS NULL"
      )
    )
  end

  def down do
    drop(table(:base_settings))
  end
end
