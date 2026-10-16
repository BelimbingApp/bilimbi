defmodule Bilimbi.Core.Person.Migrations.MoveBackfilledWorkContactsToAffiliations do
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")

    execute("""
    UPDATE #{schema}.core_people p
    SET email = NULL, phone = NULL
    FROM #{schema}.core_person_affiliations a
    WHERE a.person_id = p.id
      AND a.legacy_employee_id IS NOT NULL
      AND p.email IS NOT DISTINCT FROM a.email
      AND p.phone IS NOT DISTINCT FROM a.phone
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    execute("""
    UPDATE #{schema}.core_people p
    SET email = a.email, phone = a.phone
    FROM #{schema}.core_person_affiliations a
    WHERE a.person_id = p.id
      AND a.legacy_employee_id IS NOT NULL
      AND p.email IS NULL
      AND p.phone IS NULL
    """)
  end

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
end
