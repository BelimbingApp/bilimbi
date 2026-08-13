defmodule Bilimbi.Base.Tenancy.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.tenancy",
          label: "Tenancy",
          icon: "building-library",
          parent: "admin",
          order: 80
        },
        %{
          id: "admin.tenancy.tenant",
          label: "Tenants",
          parent: "admin.tenancy",
          route: "/tenancy/tenants",
          capability: "admin.tenancy.tenant.list",
          order: 10
        }
      ],
      authz: %{
        capabilities: [
          "admin.tenancy.tenant.list",
          "admin.tenancy.tenant.create"
        ]
      }
    }
  end
end
