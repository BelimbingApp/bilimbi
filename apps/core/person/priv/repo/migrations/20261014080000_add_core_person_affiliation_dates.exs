defmodule Bilimbi.Core.Person.Migrations.AddCorePersonAffiliationDates do
  use Ecto.Migration

  def up do
    alter table(:core_person_affiliations) do
      add(:started_on, :date)
      add(:ended_on, :date)
    end

    flush()
    schema = quote_identifier(prefix() || "public")

    execute("""
    UPDATE #{schema}.core_person_affiliations
    SET started_on = created_at::date, ended_on = unlinked_at::date
    """)

    [[employees]] =
      Ecto.Adapters.SQL.query!(repo(), "SELECT to_regclass($1) IS NOT NULL", [
        schema <> ".employees"
      ]).rows

    if employees do
      execute("""
      UPDATE #{schema}.core_person_affiliations a
      SET started_on = COALESCE(e.employment_start, a.started_on),
          ended_on = COALESCE(e.employment_end, a.ended_on)
      FROM #{schema}.employees e
      WHERE a.legacy_employee_id = e.id
      """)
    end
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    [[present?]] =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT EXISTS (SELECT 1 FROM #{schema}.core_person_affiliations WHERE started_on IS NOT NULL OR ended_on IS NOT NULL)",
        []
      ).rows

    if present?,
      do:
        raise(
          "cannot roll back affiliation dates while they are recorded; restore a reviewed backup"
        )

    alter table(:core_person_affiliations) do
      remove(:started_on)
      remove(:ended_on)
    end
  end

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
end
