defmodule Bilimbi.Core.Employee.SchemaContract do
  @moduledoc "Pinned PostgreSQL contract for the Core Employee compatibility baseline."

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_812_112_641

  def migration_version, do: @migration_version

  @impl true
  def tables, do: [employees(), employee_types()]

  defp employees do
    %{
      name: "employees",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "employees_id_seq"}),
        "company_id" => column(:bigint, false),
        "department_id" => column(:bigint),
        "supervisor_id" => column(:bigint),
        "employee_number" => column({:varchar, 255}, false),
        "full_name" => column({:varchar, 255}, false),
        "short_name" => column({:varchar, 255}),
        "designation" => column({:varchar, 255}),
        "employee_type" => column({:varchar, 255}, false, {:string, "full_time"}),
        "job_description" => column(:text),
        "email" => column({:varchar, 255}),
        "mobile_number" => column({:varchar, 255}),
        "status" => column({:varchar, 255}, false, {:string, "active"}),
        "employment_start" => column(:date),
        "employment_end" => column(:date),
        "metadata" => column(:json),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "employees_pkey" => index(["id"], true),
        "employees_employee_number_index" => index(["employee_number"]),
        "employees_employee_type_index" => index(["employee_type"]),
        "employees_email_index" => index(["email"]),
        "employees_status_index" => index(["status"]),
        "employees_company_id_employee_number_unique" =>
          index(["company_id", "employee_number"], true)
      },
      foreign_keys: %{
        "employees_company_id_foreign" => foreign_key("company_id", "companies", :cascade),
        "employees_department_id_foreign" =>
          foreign_key("department_id", "company_departments", :nilify_all),
        "employees_supervisor_id_foreign" =>
          foreign_key("supervisor_id", "employees", :nilify_all)
      }
    }
  end

  defp employee_types do
    %{
      name: "employee_types",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "employee_types_id_seq"}),
        "code" => column({:varchar, 255}, false),
        "label" => column({:varchar, 255}, false),
        "is_system" => column(:boolean, false, {:boolean, false}),
        "company_id" => column(:bigint),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "employee_types_pkey" => index(["id"], true),
        "employee_types_company_id_index" => index(["company_id"]),
        "employee_types_company_id_code_index" => index(["company_id", "code"])
      },
      optional_indexes: %{
        "employee_types_code_unique" => index(["code"], true),
        "employee_types_global_code_unique" => index(["code"], true, "company_id IS NULL"),
        "employee_types_company_code_unique" =>
          index(["company_id", "code"], true, "company_id IS NOT NULL")
      },
      optional_checks: %{
        "employee_types_system_company_check" => check("NOT is_system OR (company_id IS NULL)")
      },
      optional_groups: [
        %{
          name: "core/employee type tenancy adaptation",
          indexes: [
            "employee_types_global_code_unique",
            "employee_types_company_code_unique"
          ],
          checks: [
            "employee_types_system_company_check"
          ]
        }
      ],
      foreign_keys: %{}
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false, where \\ nil),
    do: %{columns: columns, unique: unique, where: where}

  defp foreign_key(column, table, on_delete) do
    %{
      columns: [column],
      references: {table, ["id"]},
      on_delete: on_delete
    }
  end

  defp check(expression), do: %{expression: expression, validated: true}
end
