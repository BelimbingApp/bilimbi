defmodule Bilimbi.Core.Employee.ProductionSeedsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Database.ProductionSeedProvider
  alias Bilimbi.Core.Employee.ProductionSeeds

  test "registers an explicit production seed provider" do
    assert Application.fetch_env!(
             :bilimbi_core_employee,
             :bilimbi_production_seed_provider
           ) == ProductionSeeds

    behaviours =
      ProductionSeeds.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert ProductionSeedProvider in behaviours
  end
end
