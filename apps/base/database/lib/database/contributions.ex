defmodule Bilimbi.Base.Database.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @capabilities [
    "admin.system.database-table.list",
    "admin.system.database-table.view",
    "admin.system.database-table.edit",
    "admin.system.database-backup.list",
    "admin.system.database-backup.create",
    "admin.system.database-backup.delete",
    "admin.system.database-backup.manage",
    "admin.system.database-residue.view",
    "admin.system.database-residue.manage",
    "admin.system.data-share.view",
    "admin.system.data-share.create",
    "admin.system.data-share.delete",
    "admin.system.data-share-offer.create",
    "admin.system.data-share-offer.manage",
    "admin.system.data-share-offer.accept",
    "admin.system.data-share-plan.review",
    "admin.system.data-share-apply.execute",
    "admin.system.data-share-mirror.execute",
    "admin.system.data-share-settings.manage",
    "admin.system.data-operations.view"
  ]

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: @capabilities,
        roles: %{
          "system_viewer" => %{
            capabilities: [
              "admin.system.database-table.list",
              "admin.system.database-table.view"
            ]
          }
        }
      }
    }
  end
end
