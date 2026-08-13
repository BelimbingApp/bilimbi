defmodule Bilimbi.Core.Company.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
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
