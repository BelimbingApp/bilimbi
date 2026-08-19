defmodule Bilimbi.Core.Company.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @settings %{
    "localization.timezone" => %{
      type: :string,
      scopes: [:tenant, :company],
      default: "UTC",
      label: "Timezone",
      help: "Default timezone for this company.",
      editable: "company.profile",
      capability: "admin.company.update"
    }
  }

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.company",
          label: "Companies",
          icon: "building-office-2",
          parent: "admin",
          route: "/companies",
          capability: "admin.company.list",
          order: 10
        },
        %{
          id: "admin.company.department-type",
          label: "Department Types",
          parent: "admin.company",
          route: "/companies/department-types",
          capability: "admin.company.list",
          order: 10
        },
        %{
          id: "admin.company.legal-entity-type",
          label: "Legal Entity Types",
          parent: "admin.company",
          route: "/companies/legal-entity-types",
          capability: "admin.company.list",
          order: 20
        }
      ],
      settings: %{definitions: @settings, runtime_claims: []},
      authz: %{
        domains: %{"core" => "Core platform modules"},
        capabilities: [
          "admin.company.view",
          "admin.company.list",
          "admin.company.create",
          "admin.company.update",
          "admin.company.delete"
        ],
        roles: %{
          "tenant_owner" => %{
            capabilities: [
              "admin.company.view",
              "admin.company.list",
              "admin.company.update"
            ]
          }
        },
        company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
      }
    }
  end
end
