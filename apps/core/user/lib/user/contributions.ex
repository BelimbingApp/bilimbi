defmodule Bilimbi.Core.User.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @read_capabilities ["admin.user.list", "admin.user.view"]
  @write_capabilities ["admin.user.create", "admin.user.update", "admin.user.delete"]

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: @read_capabilities ++ @write_capabilities,
        roles: %{
          "user_viewer" => %{
            name: "User Viewer",
            description: "Read-only access to user management.",
            capabilities: @read_capabilities
          },
          "user_editor" => %{
            name: "User Editor",
            description: "Read-write access to user management.",
            capabilities: @read_capabilities ++ @write_capabilities
          }
        }
      }
    }
  end
end
