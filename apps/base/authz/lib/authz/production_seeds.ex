defmodule Bilimbi.Base.Authz.ProductionSeeds do
  @moduledoc false

  @behaviour Bilimbi.Base.Database.ProductionSeedProvider

  alias Bilimbi.Base.Authz.SystemRoleReconciler
  alias Bilimbi.Base.Database
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @impl true
  def production_seeds do
    [
      Database.production_seed!(
        :bilimbi_base_authz,
        "system-roles",
        {__MODULE__, :reconcile, []}
      )
    ]
  end

  @doc false
  def reconcile(repo) do
    registry = ContributionRegistry.install!().consumers.authz

    case SystemRoleReconciler.reconcile(repo, registry) do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
