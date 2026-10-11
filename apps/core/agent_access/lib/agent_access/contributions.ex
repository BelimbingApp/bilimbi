defmodule Bilimbi.Core.AgentAccess.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "agent_access.oauth_requests_per_minute" => %{
            type: :integer,
            scopes: [:global],
            default: 60,
            minimum: 1,
            maximum: 10_000,
            label: "OAuth requests per minute",
            help:
              "Maximum device or token requests per sender address per minute on each host node.",
            editable: "operator",
            capability: "base.settings.global.manage"
          }
        },
        runtime_claims: []
      }
    }
  end
end
