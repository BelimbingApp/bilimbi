defmodule Bilimbi.Base.Session.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @list "admin.system.session.list"

  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "session.last_activity_touch_minutes" => %{
            type: :integer,
            scopes: [:global],
            default: 5,
            minimum: 1,
            maximum: 60,
            label: "Session activity update interval",
            help: "Minimum minutes between stored activity updates for an active session.",
            editable: "operator",
            capability: "base.settings.global.manage"
          },
          "session.retention_days" => %{
            type: :integer,
            scopes: [:global],
            default: 30,
            minimum: 1,
            maximum: 3650,
            label: "Session retention",
            help: "Days of inactive session metadata to retain.",
            editable: "operator",
            capability: "base.settings.global.manage"
          }
        },
        runtime_claims: []
      },
      schedule: %{
        definitions: [
          %{
            key: "base/session.retention",
            name: "Prune expired sessions",
            expression: "7 3 * * *",
            timezone: "Etc/UTC",
            task_name: "Base Session retention",
            worker: Bilimbi.Base.Session.RetentionWorker,
            args: %{},
            overlap: :forbid,
            misfire: :coalesce
          }
        ]
      },
      menu: [
        %{
          id: "admin.system.session",
          label: "Sessions",
          parent: "admin.system.diagnostics",
          route: "/system/sessions",
          capability: "admin.system.session.list",
          order: 50
        }
      ],
      authz: %{
        capabilities: [@list, "admin.system.session.manage"],
        roles: %{
          "auditor" => %{capabilities: [@list]},
          "system_viewer" => %{capabilities: [@list]}
        }
      }
    }
  end
end
