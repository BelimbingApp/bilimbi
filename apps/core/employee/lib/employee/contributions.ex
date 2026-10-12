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
      grid: Bilimbi.Core.Employee.GridTables.tables(),
      agent_api: %{
        operations: Bilimbi.Core.Employee.AgentOperations.declarations(),
        guides: [
          %{
            key: "core.employee",
            title: "People at companies",
            summary:
              "Record a person as an employee of an existing employer company, including external companies.",
            keywords: ["person", "employer", "employee"],
            capability: "admin.employee.list",
            body: """
            An employee is a person employed by a company. It is separate from a
            login account. Confirm that an employee record matches the intended
            relationship; source contact details alone do not establish employment.
            A person belongs to their own employer, not to the company where you
            signed in. Search `core.company.list` first and
            reuse an existing employer. If missing, create the employer through a
            reviewed plan and use its returned id in the person's next plan.

            Search `core.employee.list` by name, email or employee number with
            `employer_company_id` before creating a person. Omit the target only
            when searching your signed-in company. Work at another company requires
            the same tenant-wide company permission as the form's selector.

            `core.employee.create` needs the employer id, full name and an employee
            number unique within that employer. Ask for the company's numbering
            convention when it is unknown. Do not use SYS-001, the platform's
            reserved identity. Designation, email and mobile number are optional;
            send only facts the source supports. Employee type defaults to full_time
            and status to active, as shown in the preview. Neither creates a login.
            Review the dry run with the person and commit its exact plan code;
            company approval workflows and the agent-write switch still apply.
            """
          }
        ]
      },
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
