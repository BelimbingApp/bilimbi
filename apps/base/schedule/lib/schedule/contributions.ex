defmodule Bilimbi.Base.Schedule.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.schedule.view"
  @execute "admin.system.schedule.execute"
  @manage "admin.system.schedule.manage"

  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "schedule.history.keep_days" => %{
            type: :integer,
            scopes: [:global],
            default: 90,
            minimum: 0,
            maximum: 3650,
            label: "Schedule history retention",
            help: "Days of operational schedule history to retain; zero disables pruning.",
            editable: "operator",
            capability: @manage
          }
        },
        runtime_claims: []
      },
      menu: [
        %{
          id: "admin.system.schedule",
          label: "Schedule",
          icon: "clipboard-document-list",
          parent: "admin.system",
          route: "/system/schedule",
          capability: @view,
          order: 15
        }
      ],
      authz: %{
        capabilities: [@view, @execute, @manage],
        roles: %{"system_viewer" => %{capabilities: [@view]}}
      },
      schedule: %{definitions: []}
    }
  end
end
