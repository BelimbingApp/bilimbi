defmodule Bilimbi.Base.Locale.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "ui.locale" => %{
            type: :string,
            scopes: [:user, :global],
            default: "en-MY",
            label: "Locale",
            help: "Language and regional formatting used for this account or installation."
          }
        },
        runtime_claims: ["ui.locale_inferred_country", "ui.locale_source"]
      }
    }
  end
end
