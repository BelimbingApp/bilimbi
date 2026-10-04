defmodule Bilimbi.Base.Session.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @list "admin.system.session.list"

  @impl true
  def contributions do
    %{
      dashboard: [
        %{
          id: "base-dashboard-session-stats",
          label: "Sessions",
          embed: "dashboard.sessions",
          size: :small,
          order: 40,
          capability: @list,
          refresh_interval: 60_000
        }
      ],
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
          "session.lifetime_minutes" => %{
            type: :integer,
            scopes: [:global],
            default: 120,
            minimum: 1,
            maximum: 525_600,
            label: "Session lifetime",
            help: "Minutes of inactivity before a sign-in expires.",
            editable: "operator",
            capability: "admin.system.session.manage"
          }
        },
        runtime_claims: []
      },
      schedule: %{
        definitions: [
          %{
            key: "base/session-expiry",
            name: "Prune expired sessions",
            expression: "*/5 * * * *",
            timezone: "Etc/UTC",
            task_name: "Base Session expiry",
            worker: Bilimbi.Base.Session.ExpiryWorker,
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
        platform_capabilities: [@list, "admin.system.session.manage"],
        roles: %{
          "auditor" => %{capabilities: [@list]},
          "system_viewer" => %{capabilities: [@list]}
        }
      }
    }
  end
end
