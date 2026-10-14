defmodule Bilimbi.Base.AgentApi.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  def contributions do
    %{
      settings: %{
        definitions: %{
          "agent_api.mcp_requests_per_minute" => %{
            type: :integer,
            scopes: [:global],
            default: 120,
            minimum: 1,
            maximum: 10_000,
            label: "MCP requests per minute",
            help: "Maximum MCP requests per sender address per minute on each host node.",
            editable: "operator",
            capability: "base.settings.global.manage"
          },
          "agent_api.plan_expiry_seconds" => %{
            type: :integer,
            scopes: [:global],
            default: 600,
            minimum: 60,
            maximum: 3600,
            label: "Agent plan lifetime",
            help: "Seconds to review and commit an agent write plan.",
            editable: "operator",
            capability: "base.settings.global.manage"
          },
          "agent_api.plan_max_operations" => %{
            type: :integer,
            scopes: [:global],
            default: 20,
            minimum: 1,
            maximum: 100,
            label: "Operations per agent plan",
            help: "Maximum number of writes in one reviewed plan.",
            editable: "operator",
            capability: "base.settings.global.manage"
          }
        },
        runtime_claims: []
      }
    }
  end
end
