defmodule Bilimbi.Base.Schedule.DescriptorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Schedule.Contributions
  alias Bilimbi.Base.Settings.ContributionValidator

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

  test "history retention contribution is bounded and accepted by Settings" do
    payload = Contributions.contributions().settings

    assert %{definitions: %{"schedule.history.keep_days" => definition}} =
             ContributionValidator.validate_contributions!([
               %{descriptor: %{id: "base/schedule"}, payload: payload}
             ])

    assert definition.default == 90
    assert definition.minimum == 0
    assert definition.maximum == 3650
    assert Bilimbi.Base.Settings.Definition.accepts?(definition, 0)
    assert Bilimbi.Base.Settings.Definition.accepts?(definition, 3650)
    refute Bilimbi.Base.Settings.Definition.accepts?(definition, -1)
    refute Bilimbi.Base.Settings.Definition.accepts?(definition, 3651)
  end
end
