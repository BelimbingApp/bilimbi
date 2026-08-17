defmodule Bilimbi.Core.Employee.Migrations.AdaptEmployeeTypesTenancyIndexes do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:employee_types, [:code], name: :employee_types_code_unique)

    create unique_index(:employee_types, [:code],
             where: "company_id IS NULL AND is_system = true",
             name: :employee_types_global_code_unique
           )

    create unique_index(:employee_types, [:company_id, :code],
             where: "company_id IS NOT NULL",
             name: :employee_types_company_code_unique
           )

    schema = quote_identifier(prefix() || "public")

    execute(
      """
      ALTER TABLE #{schema}.employee_types
      ADD CONSTRAINT employee_types_custom_company_check
      CHECK (is_system = (company_id IS NULL))
      """,
      """
      ALTER TABLE #{schema}.employee_types
      DROP CONSTRAINT IF EXISTS employee_types_custom_company_check
      """
    )
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    execute(
      "ALTER TABLE #{schema}.employee_types DROP CONSTRAINT IF EXISTS employee_types_custom_company_check"
    )

    drop_if_exists unique_index(:employee_types, [:company_id, :code],
                     name: :employee_types_company_code_unique
                   )

    drop_if_exists unique_index(:employee_types, [:code],
                     name: :employee_types_global_code_unique
                   )

    # Note: Reversing to a global unique index requires that no two companies have
    # created custom employee types with the same code. In a multi-tenant dataset,
    # duplicate codes must be reconciled before executing down.
    create unique_index(:employee_types, [:code], name: :employee_types_code_unique)
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
