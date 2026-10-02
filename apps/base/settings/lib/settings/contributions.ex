defmodule Bilimbi.Base.Settings.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      settings: %{definitions: webhook_definitions(), runtime_claims: []},
      # Belimbing declares this item in Base/System, which Bilimbi has no
      # equivalent of; the page lives here, so the item does too. Same id.
      menu: [
        %{
          id: "admin.system.settings",
          label: "Settings",
          icon: "cog-6-tooth",
          parent: "admin.system",
          route: "/system/settings",
          capability: "base.settings.global.manage",
          order: 10
        }
      ],
      authz: %{
        domains: %{"base" => "Framework-owned application capabilities"},
        capabilities: [
          "base.settings.global.manage",
          "base.settings.company.manage",
          "base.settings.user.manage",
          "base.settings.support-override.manage",
          "base.settings.secret.view"
        ]
      }
    }
  end

  # The host consumes these platform-wide settings; the existing Settings
  # operator UI renders them with its normal authorization and validation.
  defp webhook_definitions do
    Map.new(
      [
        {"max_bytes", 1_048_576, 67_108_864, "Webhook body limit",
         "Maximum bytes per inbound webhook."},
        {"rate_limit", 120, 1_000_000, "Webhook delivery limit",
         "Maximum verified deliveries per registered handler per window, on each host node."},
        {"sender_rate_limit", 120, 1_000_000, "Webhook sender limit",
         "Maximum attempts per sender address per registered handler per window, on each host node, before verification."},
        {"failure_limit", 60, 1_000_000, "Webhook failure audit limit",
         "Failed attempts per registered handler per window audited individually; later failures are counted in one audit row when the window closes."},
        {"window_ms", 60_000, 3_600_000, "Webhook rate window", "Rate window in milliseconds."},
        {"read_timeout_ms", 15_000, 120_000, "Webhook read timeout",
         "Maximum wait in milliseconds for each body read."}
      ],
      fn {key, default, maximum, label, help} ->
        {"webhooks." <> key,
         %{
           type: :integer,
           scopes: [:global],
           default: default,
           minimum: 1,
           maximum: maximum,
           label: label,
           help: help,
           editable: "operator",
           capability: "base.settings.global.manage"
         }}
      end
    )
  end
end
