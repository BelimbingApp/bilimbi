defmodule Bilimbi.Base.System.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.info.view"
  @inspector "admin.system.menu-inspector.view"

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
        },
        %{
          id: "admin.system.menu-inspector",
          label: "Menu Inspector",
          icon: "magnifying-glass",
          parent: "admin.system.diagnostics",
          route: "/system/menu-inspector",
          capability: @inspector,
          order: 10
        }
      ],
      authz: %{
        capabilities: [@view, @inspector],
        roles: %{
          "system_viewer" => %{capabilities: [@view, @inspector]}
        }
      }
    }
  end
end
