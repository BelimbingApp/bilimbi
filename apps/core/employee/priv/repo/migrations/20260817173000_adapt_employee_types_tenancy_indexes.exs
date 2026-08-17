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
  end

  def down do
    drop_if_exists unique_index(:employee_types, [:company_id, :code],
                     name: :employee_types_company_code_unique
                   )

    drop_if_exists unique_index(:employee_types, [:code],
                     name: :employee_types_global_code_unique
                   )

    create unique_index(:employee_types, [:code], name: :employee_types_code_unique)
  end
end
