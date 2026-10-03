defmodule Bilimbi.Base.Workflow.Contributions do
  @moduledoc false
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @approve "admin.reference.record.approve"

  @impl true
  def contributions do
    %{
      authz: %{
        capabilities: [@approve]
      }
    }
  end
end
