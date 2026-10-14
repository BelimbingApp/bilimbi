defmodule Bilimbi.Core.Person.Migrations.CreateCorePeople do
  use Ecto.Migration

  def up do
    create table(:core_people) do
      add(:tenant_id, references(:tenants, on_delete: :restrict), null: false)
      add(:full_name, :string, null: false)
      add(:email, :string)
      add(:phone, :string)
      add(:retired_at, :naive_datetime)
      timestamps(type: :naive_datetime, inserted_at: :created_at, null: true)
    end

    create(index(:core_people, [:tenant_id, :full_name]))
    create(unique_index(:core_people, [:id, :tenant_id]))

    create table(:core_person_affiliations) do
      add(:tenant_id, references(:tenants, on_delete: :restrict), null: false)
      add(:person_id, :bigint, null: false)
      add(:company_id, references(:companies, on_delete: :restrict), null: false)
      add(:title, :string)
      add(:email, :string)
      add(:phone, :string)
      # An explicit, durable mapping, deliberately not a foreign key: People
      # can claim/remove legacy HR storage without destroying the mapping.
      add(:legacy_employee_id, :bigint)
      add(:unlinked_at, :naive_datetime)
      timestamps(type: :naive_datetime, inserted_at: :created_at, null: true)
    end

    create(unique_index(:core_person_affiliations, [:legacy_employee_id]))

    create(
      unique_index(:core_person_affiliations, [:person_id, :company_id],
        name: :core_person_affiliations_live_unique,
        where: "unlinked_at IS NULL"
      )
    )

    create(index(:core_person_affiliations, [:tenant_id, :person_id]))

    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.core_person_affiliations
    ADD CONSTRAINT core_person_affiliations_person_tenant_foreign
    FOREIGN KEY (person_id, tenant_id) REFERENCES #{schema}.core_people (id, tenant_id)
    ON DELETE RESTRICT
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    [[present?]] =
      Ecto.Adapters.SQL.query!(repo(), "SELECT EXISTS (SELECT 1 FROM #{schema}.core_people)", []).rows

    if present?,
      do:
        raise(
          "cannot roll back Core Person while identity or affiliation history exists; restore a reviewed backup"
        )

    drop(table(:core_person_affiliations))
    drop(table(:core_people))
  end

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
end
