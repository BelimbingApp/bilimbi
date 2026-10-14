defmodule Bilimbi.Core.Employee.Migrations.BackfillCorePersonIdentities do
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")
    # Copy identity/affiliation facts only; employees, its IDs, user links,
    # department heads, system agents and all HR data stay byte-for-byte.
    # Company owns the tenant reference on the adopted employee employer.
    execute("""
    INSERT INTO #{schema}.core_people (id, tenant_id, full_name, email, phone, created_at, updated_at)
    SELECT e.id, c.tenant_id, e.full_name, e.email, e.mobile_number, e.created_at, e.updated_at
    FROM #{schema}.employees e JOIN #{schema}.companies c ON c.id = e.company_id
    """)

    execute("""
    INSERT INTO #{schema}.core_person_affiliations
      (tenant_id, person_id, company_id, title, email, phone, legacy_employee_id, created_at, updated_at)
    SELECT c.tenant_id, e.id, e.company_id, e.designation, e.email, e.mobile_number, e.id, e.created_at, e.updated_at
    FROM #{schema}.employees e JOIN #{schema}.companies c ON c.id = e.company_id
    """)

    execute("""
    SELECT setval(pg_get_serial_sequence('#{schema}.core_people', 'id'),
      COALESCE((SELECT max(id) FROM #{schema}.core_people), 1),
      EXISTS (SELECT 1 FROM #{schema}.core_people))
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    [[present?]] =
      Ecto.Adapters.SQL.query!(repo(), "SELECT EXISTS (SELECT 1 FROM #{schema}.core_people)", []).rows

    if present?,
      do:
        raise(
          "cannot roll back Core Employee identity backfill while person identity history exists"
        )

    :ok
  end

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
end
