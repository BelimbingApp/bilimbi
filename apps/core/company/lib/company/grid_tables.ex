defmodule Bilimbi.Core.Company.GridTables do
  @moduledoc """
  What Core Company puts in the grid catalog: `companies` with their parent
  and children, `departments` with their company, and `legal_entity_types`.
  Links to employees, users and addresses are declared by those modules,
  which depend on this one.
  """

  alias Bilimbi.Core.Company.Grid.CompaniesSource
  alias Bilimbi.Core.Company.Grid.DepartmentsSource
  alias Bilimbi.Core.Company.Grid.LegalEntityTypesSource

  @doc false
  def tables do
    %{
      tables: [
        %{
          id: "companies",
          label: "Companies",
          capability: "admin.company.list",
          source: CompaniesSource,
          key: "id",
          label_field: "name",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "name", label: "Name", type: :string},
            %{id: "code", label: "Code", type: :string},
            %{
              id: "status",
              label: "Status",
              type: :enum,
              values: ~w(active suspended pending archived)
            },
            %{id: "legal_name", label: "Legal name", type: :string},
            %{id: "registration_number", label: "Registration number", type: :string},
            %{id: "tax_id", label: "Tax ID", type: :string},
            %{id: "jurisdiction", label: "Jurisdiction", type: :string},
            %{id: "email", label: "Email", type: :string},
            %{id: "website", label: "Website", type: :string},
            %{id: "created_at", label: "Created", type: :datetime},
            %{id: "updated_at", label: "Updated", type: :datetime},
            %{id: "parent_id", type: :integer, hidden: true},
            %{id: "legal_entity_type_id", type: :integer, hidden: true}
          ],
          links: [
            %{
              id: "parent",
              label: "Parent company",
              to: "companies",
              kind: :one,
              on: {"parent_id", "id"}
            },
            %{
              id: "children",
              label: "Subsidiaries",
              to: "companies",
              kind: :many,
              on: {"id", "parent_id"}
            },
            %{
              id: "legal_entity_type",
              label: "Legal entity type",
              to: "legal_entity_types",
              kind: :one,
              on: {"legal_entity_type_id", "id"}
            },
            %{
              id: "departments",
              label: "Departments",
              to: "departments",
              kind: :many,
              on: {"id", "company_id"}
            }
          ]
        },
        %{
          id: "departments",
          label: "Departments",
          capability: "admin.company.list",
          source: DepartmentsSource,
          key: "id",
          label_field: "type_name",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "type_name", label: "Type", type: :string},
            %{id: "type_code", label: "Type code", type: :string},
            %{id: "status", label: "Status", type: :enum, values: ~w(active inactive suspended)},
            %{id: "created_at", label: "Created", type: :datetime},
            %{id: "company_id", type: :integer, hidden: true},
            %{id: "head_id", type: :integer, hidden: true}
          ],
          links: [
            %{
              id: "company",
              label: "Company",
              to: "companies",
              kind: :one,
              on: {"company_id", "id"}
            }
          ]
        },
        %{
          id: "legal_entity_types",
          label: "Legal entity types",
          capability: "admin.company.list",
          source: LegalEntityTypesSource,
          key: "id",
          label_field: "name",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "code", label: "Code", type: :string},
            %{id: "name", label: "Name", type: :string},
            %{id: "is_active", label: "Active", type: :boolean}
          ]
        }
      ]
    }
  end
end
