defmodule Bilimbi.Base.Integration.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  @list "admin.system.outbound-exchange.list"
  @payload "admin.system.outbound-exchange.payload.view"
  @delete "admin.system.outbound-exchange.delete"
  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: [@list, @payload, @delete],
        roles: %{
          "auditor" => %{capabilities: [@list]},
          "system_viewer" => %{capabilities: [@list]}
        }
      },
      menu: [
        %{
          id: "admin.system.integration",
          label: "API Exchanges",
          parent: "admin.system",
          route: "/system/api-exchanges",
          capability: @list,
          order: 45
        }
      ],
      settings: %{
        definitions: %{
          "integration.payload_retention_days" => %{
            type: :integer,
            scopes: [:global],
            default: 30,
            minimum: 1,
            maximum: 3650,
            label: "API exchange payload retention",
            help:
              "Days to retain redacted payload previews. Exchange metadata remains available.",
            editable: "operator",
            capability: @delete
          }
        },
        runtime_claims: []
      },
      schedule: %{
        definitions: [
          %{
            key: "base/integration-payload-retention",
            name: "Prune API exchange payloads",
            expression: "17 3 * * *",
            timezone: "Etc/UTC",
            task_name: "Base Integration payload retention",
            worker: Bilimbi.Base.Integration.RetentionWorker,
            args: %{},
            overlap: :forbid,
            misfire: :coalesce
          }
        ]
      }
    }
  end
end
