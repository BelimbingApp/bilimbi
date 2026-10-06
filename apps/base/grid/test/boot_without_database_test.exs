defmodule Bilimbi.Base.Grid.BootWithoutDatabaseTest do
  @moduledoc """
  The contribution snapshot is built at boot, before a migration has run.
  A table bounded by another module's facts has a source that reads the
  database while it builds its query, so nothing at boot may build one.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.ContributionValidator
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @payload %{
    tables: [
      %{
        id: "bounded",
        label: "Bounded",
        capability: "admin.test.order.view",
        source: TestSources.ReadsDatabase,
        key: "id",
        fields: [%{id: "id", type: :integer}, %{id: "label", type: :string}]
      }
    ]
  }

  test "a source that reads the database to build its query validates on an unmigrated database" do
    # The table the source reads does not exist, as no table does before
    # the first migration: building its query here is refused by PostgreSQL.
    assert_raise Postgrex.Error, ~r/grid_test_never_migrated/, fn ->
      TestSources.ReadsDatabase.query(TestFixtures.system_scope(1))
    end
  end

  test "the catalog validates at boot without building that query, and asks only for a real scope" do
    assert %{tables: %{"bounded" => bounded}} =
             ContributionValidator.validate_contributions!([
               %{descriptor: TestFixtures.descriptor(), payload: @payload}
             ])

    assert bounded.fields["label"].column == nil

    # Installed and booted. The query is first built when an account that
    # may read the table opens a catalog, which is when the database is read.
    AuthzFixtures.create_authz_tables!()
    TestFixtures.install_test_registry!(@payload)
    on_exit(&ContributionRegistry.clear_for_test!/0)

    assert Grid.catalog(TestFixtures.system_scope(1)).tables == %{}

    assert_raise Postgrex.Error, ~r/grid_test_never_migrated/, fn ->
      Grid.catalog(TestFixtures.user_scope(~w(admin.test.order.view)))
    end
  end
end
