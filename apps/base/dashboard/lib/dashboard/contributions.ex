defmodule Bilimbi.Base.Dashboard.Contributions do
  @moduledoc """
  Dashboard contribution provider. Declares the built-in widgets shipped with
  the platform baseline.

  Domain and Extension modules add their own widgets through their own
  contribution providers.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{
      menu: [],
      dashboard: [
        %{
          id: "base-dashboard-company-stats",
          label: "Companies",
          size: :small,
          order: 10
        },
        %{
          id: "base-dashboard-user-stats",
          label: "Users",
          size: :small,
          order: 20
        },
        %{
          id: "base-dashboard-session-stats",
          label: "Active Sessions",
          size: :small,
          order: 30,
          capability: "admin.session.list"
        },
        %{
          id: "base-dashboard-recent-audit",
          label: "Recent Activity",
          size: :medium,
          order: 40,
          capability: "admin.audit.log.list"
        }
      ]
    }
  end
end
