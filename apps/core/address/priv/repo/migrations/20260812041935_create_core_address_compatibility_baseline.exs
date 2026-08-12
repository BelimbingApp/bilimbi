defmodule Bilimbi.Core.Address.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:addresses, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :label, :string
      add :phone, :string
      add :line1, :text
      add :line2, :text
      add :line3, :text
      add :locality, :string
      add :postcode, :string
      add :country_iso, :string, size: 2
      add :admin1Code, :string, size: 20
      add :rawInput, :text
      add :source, :string
      add :sourceRef, :string
      add :parserVersion, :string
      add :parseConfidence, :decimal, precision: 5, scale: 4
      add :parsed_at, :naive_datetime
      add :normalized_at, :naive_datetime
      add :normalization_notes, :json
      add :verificationStatus, :string, null: false, default: "unverified"
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
      add :deleted_at, :naive_datetime

      add :tenant_id,
          references(:tenants,
            type: :bigint,
            on_delete: :restrict,
            name: :addresses_tenant_foreign
          ),
          null: false
    end

    create index(:addresses, [:country_iso])
    create index(:addresses, [:admin1Code], name: :addresses_admin1code_index)
    create index(:addresses, [:source])

    create index(:addresses, [:verificationStatus], name: :addresses_verificationstatus_index)

    create index(:addresses, [:tenant_id], name: :addresses_tenant_index)

    create table(:addressables, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :address_id,
          references(:addresses,
            type: :bigint,
            on_delete: :delete_all,
            name: :addressables_address_id_foreign
          ),
          null: false

      add :addressable_type, :string, null: false
      add :addressable_id, :bigint, null: false
      add :kind, :json, null: false, default: fragment("'[]'::json")
      add :is_primary, :boolean, null: false, default: false
      add :priority, :smallint, null: false, default: 0
      add :valid_from, :date
      add :valid_to, :date
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:addressables, [:addressable_type, :addressable_id])
    create index(:addressables, [:is_primary])
  end

  def down do
    drop table(:addressables)
    drop table(:addresses)
  end
end
