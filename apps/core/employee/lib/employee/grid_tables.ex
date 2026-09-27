defmodule Bilimbi.Core.Employee.GridTables do
  @moduledoc """
  What Core Employee puts in the grid catalog: `employees` with their
  company, department, supervisor, subordinates and type, `employee_types`,
  and the inbound links from companies and departments to their employees.
  Core Employee depends on Core Company, so it is the module that names
  `companies` and `departments`.
  """

  alias Bilimbi.Core.Employee.Grid.Edges
  alias Bilimbi.Core.Employee.Grid.EmployeesSource
  alias Bilimbi.Core.Employee.Grid.EmployeeTypesSource

  @doc false
  def tables do
    %{
      tables: [
        %{
          id: "employees",
          label: "Employees",
          capability: "admin.employee.list",
          source: EmployeesSource,
          key: "id",
          label_field: "full_name",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "employee_number", label: "Number", type: :string},
            %{id: "full_name", label: "Name", type: :string},
            %{id: "short_name", label: "Short name", type: :string},
            %{id: "designation", label: "Designation", type: :string},
            %{id: "employee_type", label: "Type code", type: :string},
            %{id: "email", label: "Email", type: :string},
            %{id: "mobile_number", label: "Mobile", type: :string},
            %{
              id: "status",
              label: "Status",
              type: :enum,
              values: ~w(pending probation active inactive terminated)
            },
            %{id: "employment_start", label: "Employment start", type: :date},
            %{id: "employment_end", label: "Employment end", type: :date},
            %{id: "created_at", label: "Created", type: :datetime},
            %{id: "company_id", type: :integer, hidden: true},
            %{id: "department_id", type: :integer, hidden: true},
            %{id: "supervisor_id", type: :integer, hidden: true}
          ],
          links: [
            %{
              id: "company",
              label: "Company",
              to: "companies",
              kind: :one,
              on: {"company_id", "id"}
            },
            %{
              id: "department",
              label: "Department",
              to: "departments",
              kind: :one,
              on: {"department_id", "id"}
            },
            %{
              id: "supervisor",
              label: "Supervisor",
              to: "employees",
              kind: :one,
              on: {"supervisor_id", "id"}
            },
            %{
              id: "subordinates",
              label: "Subordinates",
              to: "employees",
              kind: :many,
              on: {"id", "supervisor_id"}
            },
            %{
              id: "type",
              label: "Type",
              to: "employee_types",
              kind: :one,
              via: {Edges, :employee_type}
            },
            %{
              id: "employees",
              label: "Employees",
              from: "companies",
              to: "employees",
              kind: :many,
              on: {"id", "company_id"}
            },
            %{
              id: "employees",
              label: "Employees",
              from: "departments",
              to: "employees",
              kind: :many,
              on: {"id", "department_id"}
            },
            %{
              id: "head",
              label: "Head",
              from: "departments",
              to: "employees",
              kind: :one,
              on: {"head_id", "id"}
            }
          ]
        },
        %{
          id: "employee_types",
          label: "Employee types",
          capability: "admin.employee-type.list",
          source: EmployeeTypesSource,
          key: "id",
          label_field: "label",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "code", label: "Code", type: :string},
            %{id: "label", label: "Label", type: :string},
            %{id: "is_system", label: "System type", type: :boolean}
          ]
        }
      ]
    }
  end
end
