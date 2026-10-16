defmodule Bilimbi.Core.Person.Migrations.CreateCorePersonRelationships do
  use Ecto.Migration

  def up do
    create table(:core_person_relationships) do
      add(:tenant_id, references(:tenants, on_delete: :restrict), null: false)
      add(:person_id, :bigint, null: false)
      add(:company_id, references(:companies, on_delete: :restrict), null: false)

      add(:relationship_type_id, references(:company_relationship_types, on_delete: :restrict),
        null: false
      )

      add(:effective_from, :date)
      add(:effective_to, :date)
      add(:deleted_at, :naive_datetime)
      timestamps(type: :naive_datetime, inserted_at: :created_at, null: true)
    end

    create(index(:core_person_relationships, [:tenant_id, :person_id]))

    create(
      unique_index(:core_person_relationships, [:company_id, :person_id, :relationship_type_id],
        name: :core_person_relationship_live_unique,
        where: "deleted_at IS NULL AND effective_to IS NULL"
      )
    )

    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.core_person_relationships
    ADD CONSTRAINT core_person_relationships_person_tenant_foreign
    FOREIGN KEY (person_id, tenant_id) REFERENCES #{schema}.core_people (id, tenant_id)
    ON DELETE RESTRICT
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    [[present?]] =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT EXISTS (SELECT 1 FROM #{schema}.core_person_relationships)",
        []
      ).rows

    if present?,
      do:
        raise(
          "cannot roll back person roles while relationship history exists; restore a reviewed backup"
        )

    drop(table(:core_person_relationships))
  end

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
end
