defmodule Bilimbi.Core.Employee.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_employee_tables! do
    apply(Bilimbi.Core.Company.TestFixtures, :create_company_identity_tables!, [])

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE company_department_types (
        id bigserial PRIMARY KEY,
        code varchar(255) NOT NULL UNIQUE,
        name varchar(255) NOT NULL,
        category varchar(255) NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE company_departments (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        department_type_id bigint NOT NULL,
        head_id bigint,
        status varchar(255) NOT NULL DEFAULT 'active',
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE employees (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        department_id bigint,
        supervisor_id bigint,
        employee_number varchar(255) NOT NULL,
        full_name varchar(255) NOT NULL,
        short_name varchar(255),
        designation varchar(255),
        employee_type varchar(255) NOT NULL DEFAULT 'full_time',
        job_description text,
        email varchar(255),
        mobile_number varchar(255),
        status varchar(255) NOT NULL DEFAULT 'active',
        employment_start date,
        employment_end date,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT employees_company_id_employee_number_unique
          UNIQUE (company_id, employee_number),
        CONSTRAINT employees_company_id_foreign
          FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE,
        CONSTRAINT employees_department_id_foreign
          FOREIGN KEY (department_id) REFERENCES company_departments (id) ON DELETE SET NULL,
        CONSTRAINT employees_supervisor_id_foreign
          FOREIGN KEY (supervisor_id) REFERENCES employees (id) ON DELETE SET NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      ALTER TABLE company_departments
      ADD CONSTRAINT company_departments_head_id_foreign
      FOREIGN KEY (head_id) REFERENCES employees (id) ON DELETE SET NULL
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE employee_types (
        id bigserial PRIMARY KEY,
        code varchar(255) NOT NULL,
        label varchar(255) NOT NULL,
        is_system boolean NOT NULL DEFAULT false,
        company_id bigint,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT employee_types_custom_company_check CHECK (is_system = (company_id IS NULL))
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE UNIQUE INDEX employee_types_global_code_unique
      ON employee_types (code)
      WHERE company_id IS NULL AND is_system = true
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE UNIQUE INDEX employee_types_company_code_unique
      ON employee_types (company_id, code)
      WHERE company_id IS NOT NULL
      """,
      []
    )
  end

  def insert_department!(id, company_id) do
    SQL.query!(
      Repo,
      "INSERT INTO company_department_types (id, code, name, category) VALUES ($1, $2, $3, $4)",
      [id, "department_#{id}", "Department #{id}", "operations"]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO company_departments (id, company_id, department_type_id)
      VALUES ($1, $2, $1)
      """,
      [id, company_id]
    )
  end
end
