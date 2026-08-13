defmodule Bilimbi.Base.Settings.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      settings: %{definitions: %{}, runtime_claims: []},
      authz: %{
        domains: %{"base" => "Framework-owned application capabilities"},
        capabilities: [
          "base.settings.global.manage",
          "base.settings.company.manage",
          "base.settings.user.manage",
          "base.settings.support-override.manage"
        ]
      }
    }
  end
end
