defmodule Bilimbi.Base.DateTime.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  # This module owns both policy definitions (#447). Core Company keeps the
  # company-timezone management surface and resolution: it writes the value
  # through the public Settings API under its own capability and never needs
  # this module's internals; Base never queries Core.
  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "localization.timezone" => %{
            type: :string,
            scopes: [:tenant, :company],
            default: "UTC",
            label: "Timezone",
            help: "Default timezone for this company.",
            editable: "company.profile",
            capability: "admin.company.update"
          },
          "ui.timezone.mode" => %{
            type: :string,
            scopes: [:user],
            default: "company",
            label: "Time zone display",
            help:
              "How timestamps render for this account: the company time zone, " <>
                "the browser's local time zone, or stored UTC."
          }
        }
      }
    }
  end
end
