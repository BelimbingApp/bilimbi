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
             "base/audit",
             "base/authz",
             "base/database",
             "base/module_registry",
             "base/queue",
             "base/settings",
             "base/ui"
           ]

    assert descriptor[:migration_dispositions] == %{
             20_260_813_114_301 => :compatible_baseline,
             20_260_821_100_001 => :bilimbi_only
           }

    assert descriptor[:schema_contract] == Bilimbi.Base.Schedule.SchemaContract
    assert descriptor[:contribution_provider] == Bilimbi.Base.Schedule.Contributions
    assert descriptor[:web] == "priv/web_routes.exs"
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

  test "operator route and menu require the dedicated view capability" do
    contributions = Contributions.contributions()

    assert [
             %{
               id: "admin.system.schedule",
               route: "/system/schedule",
               capability: "admin.system.schedule.view"
             }
           ] = contributions.menu

    assert Enum.sort(contributions.authz.capabilities) ==
             Enum.sort([
               "admin.system.schedule.view",
               "admin.system.schedule.execute",
               "admin.system.schedule.manage"
             ])

    {routes, _binding} = Code.eval_file(Path.expand("../priv/web_routes.exs", __DIR__))

    assert [
             %{
               path: "/system/schedule",
               live: Bilimbi.Base.Schedule.Web.IndexLive,
               session: :auth,
               capability: "admin.system.schedule.view"
             }
           ] = routes
  end
end
