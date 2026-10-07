defmodule Bilimbi.Core.Company.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      dashboard: [
        %{
          id: "base-dashboard-company-stats",
          label: "Companies",
          embed: "dashboard.companies",
          size: :small,
          order: 10
        },
        %{
          id: "current-company",
          label: "Your Company",
          embed: "dashboard.company",
          placement: :section,
          order: 10
        }
      ],
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
      grid: Bilimbi.Core.Company.GridTables.tables(),
      authz: %{
        domains: %{"core" => "Core platform modules"},
        # `admin.company.sensitive.view` is field-level: it shows the tax ID
        # and email of a company the reader may already open
        # (`Bilimbi.Core.Company.Summary.field_policy/0`). It is granted to
        # the configured owner role so an installation keeps seeing what it
        # saw; `mix bilimbi.authz.reconcile` carries it into an existing
        # database.
        capabilities: [
          "admin.company.view",
          "admin.company.list",
          "admin.company.create",
          "admin.company.update",
          "admin.company.delete",
          "admin.company.sensitive.view",
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
              "admin.company.sensitive.view",
              "admin.company.tenant-wide.manage"
            ]
          }
        },
        company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
      }
    }
  end
end
