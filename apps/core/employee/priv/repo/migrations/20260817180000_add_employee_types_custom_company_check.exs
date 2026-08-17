defmodule Bilimbi.Core.Employee.Migrations.AddEmployeeTypesCustomCompanyCheck do
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")

    # Drop index with narrower predicate (is_system = true) from 20260817173000
    execute("""
    DROP INDEX IF EXISTS #{schema}.employee_types_global_code_unique
    """)

    # Broaden the global partial index to cover ALL company_id IS NULL rows
    # (both system types and adopted Belimbing global custom types)
    execute("""
    CREATE UNIQUE INDEX employee_types_global_code_unique
    ON #{schema}.employee_types (code)
    WHERE (company_id IS NULL)
    """)

    # Enforce that system types cannot belong to a company
    execute("""
    ALTER TABLE #{schema}.employee_types
    ADD CONSTRAINT employee_types_system_company_check
    CHECK (NOT is_system OR (company_id IS NULL))
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.employee_types
    DROP CONSTRAINT IF EXISTS employee_types_system_company_check
    """)

    execute("""
    DROP INDEX IF EXISTS #{schema}.employee_types_global_code_unique
    """)

    execute("""
    CREATE UNIQUE INDEX employee_types_global_code_unique
    ON #{schema}.employee_types (code)
    WHERE (company_id IS NULL AND is_system = true)
    """)
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
