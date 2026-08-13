defmodule Bilimbi.Core.Employee.ProductionSeedsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.ProductionSeedProvider
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.ProductionSeeds

  defmodule RepoSpy do
    @moduledoc false

    def all(_query) do
      send(self(), :repo_all)
      []
    end

    def insert_all(schema, rows, opts) do
      send(self(), {:repo_insert_all, schema, rows, opts})
      {length(rows), nil}
    end
  end

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

  test "runs the system-type seed through the repo supplied by the runner" do
    assert [seed] = ProductionSeeds.production_seeds()
    assert :ok = ProductionSeed.invoke(seed, RepoSpy)

    assert_received :repo_all

    assert_received {:repo_insert_all, EmployeeType, rows, opts}

    assert length(rows) == 5

    assert opts == [
             conflict_target: [:code],
             on_conflict: {:replace, [:label, :is_system, :company_id, :updated_at]}
           ]
  end
end
