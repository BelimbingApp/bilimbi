defmodule Bilimbi.Base.UI.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.design-library.view"

  @impl true
  def contributions do
    %{
      settings: %{definitions: %{}, runtime_claims: []},
      menu: [
        %{
          id: "admin.system.design-library",
          label: "Design Library",
          icon: "paint-brush",
          parent: "admin.system",
          capability: @view,
          order: 95
        },
        %{
          id: "admin.system.design-library.components",
          label: "Components",
          parent: "admin.system.design-library",
          route: "/system/design-library/components",
          capability: @view
        },
        %{
          id: "admin.system.design-library.design-spec",
          label: "Design Spec",
          parent: "admin.system.design-library",
          route: "/system/design-library/design-spec",
          capability: @view
        },
        %{
          id: "admin.system.design-library.graphic",
          label: "Graphic",
          parent: "admin.system.design-library",
          route: "/system/design-library/graphic",
          capability: @view
        },
        %{
          id: "admin.system.design-library.theme",
          label: "Theme",
          parent: "admin.system.design-library",
          route: "/system/design-library",
          capability: @view
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
