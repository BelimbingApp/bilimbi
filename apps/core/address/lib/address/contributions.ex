defmodule Bilimbi.Core.Address.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @capabilities [
    "admin.address.view",
    "admin.address.list",
    "admin.address.create",
    "admin.address.update",
    "admin.address.delete"
  ]

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.address",
          label: "Addresses",
          icon: "map-pin",
          parent: "admin",
          route: "/addresses",
          capability: "admin.address.list",
          order: 40
        }
      ],
      authz: %{
        capabilities: @capabilities,
        roles: %{"tenant_owner" => %{capabilities: @capabilities}}
      }
    }
  end
end
