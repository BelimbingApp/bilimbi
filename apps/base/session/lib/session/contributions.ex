defmodule Bilimbi.Base.Session.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @list "admin.system.session.list"

  @impl true
  def contributions do
    %{
      menu: [
        %{
          id: "admin.system.session",
          label: "Sessions",
          parent: "admin.system.diagnostics",
          route: "/system/sessions",
          capability: "admin.system.session.list",
          order: 50
        }
      ],
      authz: %{
        capabilities: [@list, "admin.system.session.manage"],
        roles: %{
          "auditor" => %{capabilities: [@list]},
          "system_viewer" => %{capabilities: [@list]}
        }
      }
    }
  end
end
