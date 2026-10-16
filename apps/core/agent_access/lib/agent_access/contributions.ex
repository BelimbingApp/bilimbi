defmodule Bilimbi.Core.AgentAccess.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "agent_access.connection_days" => %{
            type: :integer,
            scopes: [:global],
            default: 90,
            minimum: 1,
            maximum: 365,
            label: "Agent connection length (days)",
            help:
              "Length of new device and OAuth connections. Existing connections keep their end dates.",
            editable: "operator",
            capability: "base.settings.global.manage"
          },
          "agent_access.oauth_clients" => %{
            type: :array,
            scopes: [:global],
            default: %{},
            label: "OAuth public clients",
            help:
              "Client IDs mapped to name and exact HTTPS redirect_uris. Register ChatGPT's callback here before connecting MCP.",
            validator:
              {Bilimbi.Core.AgentAccess.OAuthClient, :valid_clients?,
               "Use client IDs mapped to a name and non-empty HTTPS redirect_uris list."},
            editable: "operator",
            capability: "base.settings.global.manage"
          },
          "agent_access.authorization_code_seconds" => %{
            type: :integer,
            scopes: [:global],
            default: 120,
            minimum: 30,
            maximum: 600,
            label: "OAuth authorization code lifetime",
            help:
              "Seconds for a public client to redeem a consented authorization code with PKCE.",
            editable: "operator",
            capability: "base.settings.global.manage"
          },
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
