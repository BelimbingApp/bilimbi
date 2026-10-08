defmodule Bilimbi.Core.Employee.Migrations.AdaptEmployeeTypesTenancyIndexes do
  use Ecto.Migration

  alias Bilimbi.Base.Database.SchemaVerifier

  def up do
    # `employee_types_code_unique` is a unique constraint on every database
    # that reaches this migration: Laravel created it as one, and so does the
    # compatibility baseline. Dropping it as an index fails (2BP01) because
    # the constraint owns the index.
    execute """
    ALTER TABLE #{quoted_prefix()}.employee_types
    DROP CONSTRAINT employee_types_code_unique
    """

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

    execute """
    ALTER TABLE #{quoted_prefix()}.employee_types
    ADD CONSTRAINT employee_types_code_unique UNIQUE (code)
    """
  end

  defp quoted_prefix do
    SchemaVerifier.quote_identifier!(prefix() || "public")
  end
end
