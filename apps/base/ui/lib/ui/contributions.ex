defmodule Bilimbi.Base.UI.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.ui-reference.view"

  @impl true
  def contributions do
    %{
      settings: %{definitions: %{}, runtime_claims: []},
      menu: [
        %{
          id: "admin.system.ui-reference",
          label: "UI Reference",
          icon: "paint-brush",
          parent: "admin.system",
          route: "/system/ui-reference",
          capability: @view,
          order: 95
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
