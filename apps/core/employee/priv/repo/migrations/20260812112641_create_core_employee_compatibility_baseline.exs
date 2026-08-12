defmodule Bilimbi.Core.Employee.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  alias Bilimbi.Base.Database.SchemaVerifier

  def up do
    create table(:employees, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :company_id,
          references(:companies,
            type: :bigint,
            on_delete: :delete_all,
            name: :employees_company_id_foreign
          ),
          null: false

      add :department_id,
          references(:company_departments,
            type: :bigint,
            on_delete: :nilify_all,
            name: :employees_department_id_foreign
          )

      add :supervisor_id,
          references(:employees,
            type: :bigint,
            on_delete: :nilify_all,
            name: :employees_supervisor_id_foreign
          )

      add :employee_number, :string, null: false
      add :full_name, :string, null: false
      add :short_name, :string
      add :designation, :string
      add :employee_type, :string, null: false, default: "full_time"
      add :job_description, :text
      add :email, :string
      add :mobile_number, :string
      add :status, :string, null: false, default: "active"
      add :employment_start, :date
      add :employment_end, :date
      add :metadata, :json
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:employees, [:employee_number])
    create index(:employees, [:employee_type])
    create index(:employees, [:email])
    create index(:employees, [:status])
    create unique_index(:employees, [:company_id, :employee_number])

    schema = quoted_prefix()

    execute """
    ALTER TABLE #{schema}.company_departments
    ADD CONSTRAINT company_departments_head_id_foreign
    FOREIGN KEY (head_id)
    REFERENCES #{schema}.employees (id)
    ON DELETE SET NULL
    """

    create table(:employee_types, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, null: false
      add :label, :string, null: false
      add :is_system, :boolean, null: false, default: false
      add :company_id, :bigint
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:employee_types, [:code])
    create index(:employee_types, [:company_id])
    create index(:employee_types, [:company_id, :code])
  end

  def down do
    drop table(:employee_types)

    schema = quoted_prefix()

    execute """
    ALTER TABLE #{schema}.company_departments
    DROP CONSTRAINT company_departments_head_id_foreign
    """

    drop table(:employees)
  end

  defp quoted_prefix do
    SchemaVerifier.quote_identifier!(prefix() || "public")
  end
end
