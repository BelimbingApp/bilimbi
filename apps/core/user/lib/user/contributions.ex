defmodule Bilimbi.Core.User.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @read_capabilities ["admin.user.list", "admin.user.view"]
  @write_capabilities ["admin.user.create", "admin.user.update", "admin.user.delete"]

  @settings %{
    "ai.last_used_model_hints" => %{
      type: :array,
      scopes: [:user],
      default: [],
      label: "Last-used AI models",
      help: "Per-agent model hints used to restore this account’s recent AI choices.",
      editable: "ai.chat",
      capability: "base.settings.user.manage"
    },
    "ui.dashboard.layout" => %{
      type: :array,
      scopes: [:user],
      default: [],
      label: "Dashboard layout",
      help: "The ordered dashboard widgets selected by this account.",
      editable: "dashboard.customize",
      capability: "base.settings.user.manage"
    },
    "ui.landing_menu_id" => %{
      type: :string,
      scopes: [:user],
      default: "",
      label: "Landing page",
      help: "The first available menu page opened after sign-in.",
      editable: "profile.profile",
      capability: "base.settings.user.manage"
    },
    "ui.theme" => %{
      type: :string,
      scopes: [:user],
      default: "system",
      label: "Theme",
      help: "Choose a light, dark, or operating-system-controlled color theme.",
      editable: "profile.appearance",
      capability: "base.settings.user.manage"
    }
  }

  @impl true
  def contributions do
    %{
      settings: %{definitions: @settings, runtime_claims: []},
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
