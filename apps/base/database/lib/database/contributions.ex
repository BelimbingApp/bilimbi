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
      menu: [
        %{
          id: "admin.system.database-query",
          label: "Database Queries",
          icon: "circle-stack",
          parent: "admin.system.database",
          route: "/admin/system/database-queries",
          capability: "admin.system.database-table.list",
          order: 30
        }
      ],
      authz: %{
        capabilities: @capabilities,
        roles: %{
          # #650: these capabilities gate the menu and the read verbs, but the raw-SQL
          # console itself is operator-only tooling. The route and every write/execute
          # handler additionally require the platform-operator tenant via
          # `Scope.platform_operator?/1` — granting this role to a non-operator surfaces
          # the pages but never lets them run or mutate a query.
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
