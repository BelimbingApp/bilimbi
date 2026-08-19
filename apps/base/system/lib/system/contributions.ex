defmodule Bilimbi.Base.System.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.info.view"

  @impl true
  def contributions do
    %{
      settings: %{definitions: %{}, runtime_claims: []},
      menu: [
        %{
          id: "admin.system.info",
          label: "System Info",
          icon: "information-circle",
          parent: "admin.system",
          route: "/system/info",
          capability: @view,
          order: 5
        }
      ],
      authz: %{
        capabilities: [@view],
        roles: %{
          "system_viewer" => %{capabilities: [@view]}
        }
      }
    }
  end
end
