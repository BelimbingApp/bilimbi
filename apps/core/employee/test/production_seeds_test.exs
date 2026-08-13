defmodule Bilimbi.Core.Employee.ProductionSeedsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Database.ProductionSeedProvider
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.EmployeeType
  alias Bilimbi.Core.Employee.ProductionSeeds

  defmodule TrackingRepo do
    def all(query) do
      send(self(), {:all, query})
      []
    end

    def insert_all(schema, rows, opts) do
      send(self(), {:insert_all, schema, rows, opts})
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

  test "bootstraps system types through the selected repository" do
    assert :ok = Employee.ensure_system_types(TrackingRepo)

    assert_received {:all, %Ecto.Query{}}

    assert_received {:insert_all, EmployeeType, rows,
                     [
                       conflict_target: [:code],
                       on_conflict: {:replace, [:label, :is_system, :company_id, :updated_at]}
                     ]}

    assert Enum.map(rows, & &1.code) ==
             ~w(full_time part_time contractor intern agent)
  end
end
