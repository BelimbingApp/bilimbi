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
      # `localization.timezone` moved to base/datetime, the policy owner
      # (#459/#447); Company keeps the management surface and writes it
      # through the public Settings API under its own capability.
      settings: %{definitions: %{}, runtime_claims: []},
      authz: %{
        domains: %{"core" => "Core platform modules"},
        capabilities: [
          "admin.company.view",
          "admin.company.list",
          "admin.company.create",
          "admin.company.update",
          "admin.company.delete",
          "admin.company.tenant-wide.manage"
        ],
        roles: %{
          "tenant_owner" => %{
            capabilities: [
              "admin.company.view",
              "admin.company.list",
              "admin.company.create",
              "admin.company.update",
              "admin.company.delete",
              "admin.company.tenant-wide.manage"
            ]
          }
        },
        company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
      }
    }
  end
end
