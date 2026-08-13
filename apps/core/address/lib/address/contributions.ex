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
      authz: %{
        capabilities: @capabilities,
        roles: %{"tenant_owner" => %{capabilities: @capabilities}}
      }
    }
  end
end
