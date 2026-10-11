defmodule Bilimbi.Base.Workflow.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @approve "admin.reference.record.approve"

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: [@approve]
      },
      schedule: %{
        definitions: [
          %{
            key: "base/workflow-maintenance",
            name: "Reconcile workflow runs and deliver transition events",
            expression: "* * * * *",
            timezone: "Etc/UTC",
            task_name: "Base Workflow maintenance",
            worker: Bilimbi.Base.Workflow.MaintenanceWorker,
            args: %{},
            overlap: :forbid,
            misfire: :coalesce
          }
        ]
      }
    }
  end
end
