defmodule Bilimbi.Base.Tenancy.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: [
          "admin.tenancy.tenant.list",
          "admin.tenancy.tenant.create"
        ]
      }
    }
  end
end
