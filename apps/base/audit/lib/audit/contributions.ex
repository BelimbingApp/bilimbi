defmodule Bilimbi.Base.Audit.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @list "admin.audit.log.list"
  @manage "admin.audit.log.manage"
  @view "admin.audit.log.view"

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.audit",
          label: "Audit Log",
          icon: "clipboard-document-list",
          parent: "admin",
          order: 70
        },
        %{
          id: "admin.audit.action",
          label: "Actions",
          parent: "admin.audit",
          route: "/audit/actions",
          capability: @list,
          order: 10
        },
        %{
          id: "admin.audit.mutation",
          label: "Data Mutations",
          parent: "admin.audit",
          route: "/audit/mutations",
          capability: @list,
          order: 20
        }
      ],
      authz: %{
        capabilities: [@list, @manage, @view],
        roles: %{
          "auditor" => %{capabilities: [@list, @manage, @view]},
          "system_viewer" => %{capabilities: [@list, @view]}
        }
      }
    }
  end
end
