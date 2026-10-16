defmodule Bilimbi.Core.Company.ProductionSeeds do
  @moduledoc "Required relationship role defaults; operator edits are preserved."
  @behaviour Bilimbi.Base.Database.ProductionSeedProvider
  @impl true
  def production_seeds do
    [
      Bilimbi.Base.Database.production_seed!(
        :bilimbi_core_company,
        "relationship-roles",
        &Bilimbi.Core.Company.RelationshipCatalogue.ensure_defaults/1
      )
    ]
  end
end
