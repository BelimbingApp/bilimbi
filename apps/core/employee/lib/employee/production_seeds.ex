defmodule Bilimbi.Core.Employee.ProductionSeeds do
  @moduledoc "Contributes Employee's required production reference data."

  @behaviour Bilimbi.Base.Database.ProductionSeedProvider

  alias Bilimbi.Base.Database
  alias Bilimbi.Core.Employee

  @impl true
  def production_seeds do
    [
      Database.production_seed!(
        :bilimbi_core_employee,
        "system-types",
        fn repo -> Employee.ensure_system_types(repo) end
      )
    ]
  end
end
