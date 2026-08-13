defmodule Bilimbi.Core.Company.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

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
          route: "/company/department-types",
          order: 10
        },
        %{
          id: "admin.company.legal-entity-type",
          label: "Legal Entity Types",
          parent: "admin.company",
          route: "/company/legal-entity-types",
          order: 20
        }
      ],
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
