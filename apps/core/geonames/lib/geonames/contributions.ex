defmodule Bilimbi.Core.Geonames.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: ["admin.geonames.view", "admin.geonames.list"],
        roles: %{
          "tenant_owner" => %{
            capabilities: ["admin.geonames.view", "admin.geonames.list"]
          }
        }
      }
    }
  end
end
