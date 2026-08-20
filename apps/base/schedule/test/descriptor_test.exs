defmodule Bilimbi.Base.Schedule.DescriptorTest do
  use ExUnit.Case, async: true

  test "descriptor declares the exact required ownership and migration dispositions" do
    {descriptor, _binding} =
      Code.eval_file(Path.expand("../bilimbi.module.exs", __DIR__))

    assert descriptor[:id] == "base/schedule"
    assert descriptor[:required]

    assert descriptor[:dependencies] == [
             "base/authz",
             "base/database",
             "base/module_registry",
             "base/queue",
             "base/settings"
           ]

    assert descriptor[:migration_dispositions] == %{
             20_260_821_100_000 => :compatible_baseline,
             20_260_821_100_001 => :bilimbi_only
           }

    assert descriptor[:schema_contract] == Bilimbi.Base.Schedule.SchemaContract
    assert descriptor[:contribution_provider] == Bilimbi.Base.Schedule.Contributions
  end
end
