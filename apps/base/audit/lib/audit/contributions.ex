defmodule Bilimbi.Base.Audit.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

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
          capability: "admin.audit.log.list",
          order: 10
        },
        %{
          id: "admin.audit.mutation",
          label: "Data Mutations",
          parent: "admin.audit",
          route: "/audit/mutations",
          capability: "admin.audit.log.list",
          order: 20
        }
      ]
    }
  end
end
