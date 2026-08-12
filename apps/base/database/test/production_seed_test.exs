defmodule Bilimbi.Base.Database.ProductionSeedTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ProductionSeed

  test "derives durable identity and order from installed module metadata" do
    seed =
      Database.production_seed!(:bilimbi_base_database, "reference/bootstrap", fn _repo -> :ok end)

    descriptor = Application.fetch_env!(:bilimbi_base_database, :bilimbi_module)

    assert seed.id == "base/database/reference/bootstrap"
    assert seed.module_id == descriptor.id
    assert seed.module_order == descriptor.order
  end

  test "rejects unstable identities and malformed callbacks" do
    assert_raise ArgumentError, ~r/local ID is invalid/, fn ->
      Database.production_seed!(:bilimbi_base_database, "Elixir.Module", fn _repo -> :ok end)
    end

    assert_raise ArgumentError, ~r/callback must be/, fn ->
      ProductionSeed.new!(
        id: "base/database/invalid-callback",
        module_id: "base/database",
        module_order: 0,
        callback: :not_callable
      )
    end
  end
end
