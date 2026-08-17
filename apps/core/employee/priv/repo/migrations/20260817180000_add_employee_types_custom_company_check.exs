defmodule Bilimbi.Core.Employee.Migrations.AddEmployeeTypesCustomCompanyCheck do
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.employee_types
    ADD CONSTRAINT employee_types_custom_company_check
    CHECK (is_system = (company_id IS NULL))
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.employee_types
    DROP CONSTRAINT IF EXISTS employee_types_custom_company_check
    """)
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
