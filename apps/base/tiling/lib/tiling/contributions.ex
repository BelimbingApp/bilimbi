defmodule Bilimbi.Base.Tiling.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  # Any signed-in account may open the workspace: the page itself shows
  # nothing, and each tile enforces its own route capability exactly as the
  # page does when opened alone. There is no capability to declare here.
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "ui.workspace.layouts" => %{
            type: :array,
            scopes: [:user],
            default: [],
            label: "Saved workspace layouts",
            help:
              "The tiled workspace layouts this account has saved, each with a slug, a label and its tile tree.",
            capability: "base.settings.user.manage"
          },
          "ui.workspace.default" => %{
            type: :string,
            scopes: [:user],
            default: "",
            label: "Default workspace layout",
            help: "The slug of the saved layout the workspace opens with.",
            capability: "base.settings.user.manage"
          },
          "ui.workspace.shared_layouts" => %{
            type: :array,
            scopes: [:company],
            default: [],
            label: "Shared workspace layouts",
            help: "Company workspaces, optionally limited to role codes.",
            capability: "ui.workspace.publish"
          }
        },
        runtime_claims: []
      },
      authz: %{
        domains: %{"ui" => "Workspace capabilities"},
        verbs: ["publish"],
        capabilities: ["ui.workspace.publish"]
      },
      menu: [
        %{
          id: "workspace",
          label: "Workspace",
          icon: "squares-2x2",
          route: "/workspace",
          order: 100
        },
        %{
          id: "workspace.shared",
          label: "Shared workspaces",
          icon: "squares-2x2",
          route: "/workspace/shared-layouts",
          capability: "ui.workspace.publish",
          order: 101
        }
      ]
    }
  end
end
