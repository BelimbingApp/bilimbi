defmodule Bilimbi.Core.Employee.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @read_capabilities [
    "admin.employee.view",
    "admin.employee.list",
    "admin.employee-type.list",
    "admin.company.view",
    "admin.company.list",
    "admin.address.view",
    "admin.address.list",
    "admin.geonames.view",
    "admin.geonames.list"
  ]

  @write_capabilities [
    "admin.employee.create",
    "admin.employee.update",
    "admin.employee.delete",
    "admin.employee-type.create",
    "admin.employee-type.update",
    "admin.employee-type.delete",
    "admin.company.create",
    "admin.company.update",
    "admin.company.delete",
    "admin.address.create",
    "admin.address.update",
    "admin.address.delete"
  ]

  @owned_capabilities [
    "admin.employee.view",
    "admin.employee.list",
    "admin.employee.create",
    "admin.employee.update",
    "admin.employee.delete",
    "admin.employee-type.list",
    "admin.employee-type.create",
    "admin.employee-type.update",
    "admin.employee-type.delete"
  ]

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.employee",
          label: "Employees",
          icon: "user-group",
          parent: "admin",
          route: "/employees",
          capability: "admin.employee.list",
          order: 20
        },
        %{
          id: "admin.employee-type",
          label: "Employee Types",
          parent: "admin.employee",
          route: "/employee-types",
          capability: "admin.employee-type.list",
          order: 10
        }
      ],
      principal_directory: [
        Bilimbi.Core.Employee.PrincipalDirectoryProvider,
        Bilimbi.Core.Employee.EmployeeDirectoryProvider
      ],
      authz: %{
        capabilities: @owned_capabilities,
        roles: %{
          "tenant_owner" => %{
            capabilities: [
              "admin.employee.view",
              "admin.employee.list",
              "admin.employee.create",
              "admin.employee.update",
              "admin.employee.delete",
              "admin.employee-type.list"
            ]
          },
          "employee_viewer" => %{
            name: "Employee Viewer",
            description: "Read-only access to employee, company, and address data.",
            capabilities: @read_capabilities
          },
          "employee_editor" => %{
            name: "Employee Editor",
            description:
              "Read-write access to employees, employee types, companies, and addresses.",
            capabilities: @read_capabilities ++ @write_capabilities
          }
        }
      }
    }
  end
end
