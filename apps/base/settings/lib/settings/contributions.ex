defmodule Bilimbi.Base.Settings.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      settings: %{definitions: %{}, runtime_claims: []},
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
          "base.settings.support-override.manage"
        ]
      }
    }
  end
end
