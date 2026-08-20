defmodule Bilimbi.Core.Geonames.Migrations.CreatePostcodeOverrides do
  use Ecto.Migration

  def up do
    create table(:geonames_postcode_overrides, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:applied_postcode_id, :bigint, null: false)

      add(
        :country_iso,
        references(:geonames_countries,
          column: :iso,
          type: :string,
          on_delete: :restrict,
          on_update: :update_all,
          name: :geonames_postcode_overrides_country_iso_foreign
        ),
        size: 2,
        null: false
      )

      add(:postcode, :string, size: 20, null: false)
      add(:place_name, :string, size: 180, null: false)
      add(:admin1_code, :string, size: 20)
      add(:admin_name1, :string, size: 100)
      add(:admin_code1, :string, size: 20)
      add(:admin_name2, :string, size: 100)
      add(:admin_code2, :string, size: 20)
      add(:admin_name3, :string, size: 100)
      add(:admin_code3, :string, size: 20)
      add(:latitude, :decimal, precision: 10, scale: 7)
      add(:longitude, :decimal, precision: 10, scale: 7)
      add(:accuracy, :smallint)

      # A null source postcode marks an operator-created row. Otherwise these
      # fields identify the upstream row that the override supersedes.
      add(:source_country_iso, :string, size: 2)
      add(:source_postcode, :string, size: 20)
      add(:source_place_name, :string, size: 180)
      add(:source_admin1_code, :string, size: 20)
      add(:source_admin_name1, :string, size: 100)
      add(:source_admin_code1, :string, size: 20)
      add(:source_admin_name2, :string, size: 100)
      add(:source_admin_code2, :string, size: 20)
      add(:source_admin_name3, :string, size: 100)
      add(:source_admin_code3, :string, size: 20)
      add(:source_latitude, :decimal, precision: 10, scale: 7)
      add(:source_longitude, :decimal, precision: 10, scale: 7)
      add(:source_accuracy, :smallint)

      add(:lock_version, :integer, null: false, default: 1)
      timestamps(type: :naive_datetime, null: false, inserted_at: :created_at)
    end

    create(
      unique_index(:geonames_postcode_overrides, [:applied_postcode_id],
        name: :geonames_postcode_overrides_applied_postcode_id_unique
      )
    )

    create(
      index(:geonames_postcode_overrides, [:country_iso, :postcode],
        name: :geonames_postcode_overrides_country_iso_postcode_index
      )
    )
  end

  def down do
    override_table = qualified_table("geonames_postcode_overrides")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{override_table} LIMIT 1) THEN
        RAISE EXCEPTION
          'cannot roll back postcode overrides while operator corrections exist';
      END IF;
    END
    $$
    """)

    drop(table(:geonames_postcode_overrides))
  end

  defp qualified_table(table_name) do
    case prefix() do
      nil -> quote_identifier(table_name)
      prefix -> "#{quote_identifier(prefix)}.#{quote_identifier(table_name)}"
    end
  end

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    "\"#{escaped}\""
  end
end
