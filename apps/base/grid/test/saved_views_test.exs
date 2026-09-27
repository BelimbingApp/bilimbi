defmodule Bilimbi.Base.Grid.SavedViewsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Grid.SavedViews
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures

  @own Scope.user(91, 73, 41)
  @other Scope.user(92, 73, 41)
  @company Scope.company(73, 41)

  setup do
    SettingsFixtures.create_settings_table!()
    %{settings: %{definitions: declared}} = Bilimbi.Base.Grid.Contributions.contributions()

    definitions =
      Map.new(declared, fn {key, attrs} -> {key, Definition.new!(key, "base/grid", attrs)} end)

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "grid-test",
      consumers:
        Map.merge(ContributionRegistry.build!([]).consumers, %{
          settings: %{definitions: definitions, runtime_claims: []}
        })
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  defp view(overrides \\ %{}) do
    struct!(
      %View{
        table: "users",
        columns: ~w(name company.name employees:count),
        lenses: %{"employees:count" => "bar"},
        zoom: 12,
        sort: "name",
        dir: :desc,
        search: "a",
        group: nil
      },
      overrides
    )
  end

  test "an account starts with nothing saved and nothing shared" do
    assert SavedViews.list_own(@own, "users") == []
    assert SavedViews.list_shared(@company, "users") == []
    assert SavedViews.fetch(@own, @company, "users", "desk") == :error
  end

  test "saving derives a slug, keeps the view whole, and a repeated label replaces it" do
    assert {:ok, entry} = SavedViews.save(@own, :own, "  Ops   desk ", view())
    assert entry["slug"] == "ops-desk"
    assert entry["label"] == "Ops desk"
    assert entry["table"] == "users"

    assert {:ok, ^entry, :own} = SavedViews.fetch(@own, @company, "users", "ops-desk")
    restored = SavedViews.view(entry)
    assert restored.columns == ~w(name company.name employees:count)
    assert restored.lenses == %{"employees:count" => "bar"}

    assert restored.zoom == 12 and restored.sort == "name" and restored.dir == :desc and
             restored.search == "a"

    assert restored.slug == "ops-desk"
    assert restored.page == 1

    assert {:ok, replaced} = SavedViews.save(@own, :own, "Ops desk", view(%{zoom: 3}))
    assert replaced["slug"] == "ops-desk"
    assert [%{"slug" => "ops-desk"}] = SavedViews.list_own(@own, "users")
    assert SavedViews.view(replaced).zoom == 3
  end

  test "a second label with the same slug gets a numbered slug" do
    {:ok, _} = SavedViews.save(@own, :own, "Desk", view())
    {:ok, second} = SavedViews.save(@own, :own, "desk!", view())
    assert second["slug"] == "desk-2"
  end

  test "views are the account's own; another account and another table see none of them" do
    {:ok, _} = SavedViews.save(@own, :own, "Desk", view())
    assert SavedViews.list_own(@other, "users") == []
    assert SavedViews.list_own(@own, "companies") == []
  end

  test "a shared view is read by every account of the company and addressed with a prefix" do
    {:ok, shared} = SavedViews.save(@company, :shared, "Team desk", view())
    assert SavedViews.reference(shared, :shared) == "shared:team-desk"

    assert {:ok, ^shared, :shared} =
             SavedViews.fetch(@other, @company, "users", "shared:team-desk")

    assert SavedViews.fetch(@other, @company, "users", "team-desk") == :error
    assert [%{"slug" => "team-desk"}] = SavedViews.list_shared(@company, "users")
    assert SavedViews.list_own(@own, "users") == []
  end

  test "deleting removes exactly that view and refuses an unknown one" do
    {:ok, _} = SavedViews.save(@own, :own, "One", view())
    {:ok, _} = SavedViews.save(@own, :own, "Two", view())
    assert :ok = SavedViews.delete(@own, :own, "users", "one")
    assert Enum.map(SavedViews.list_own(@own, "users"), & &1["slug"]) == ["two"]
    assert :error = SavedViews.delete(@own, :own, "users", "one")
  end

  test "a blank or overlong label is refused" do
    assert {:error, :label} = SavedViews.save(@own, :own, "   ", view())
    assert {:error, :label} = SavedViews.save(@own, :own, String.duplicate("x", 61), view())
  end

  test "a shared view limited to roles opens only for accounts holding one of them" do
    {:ok, everyone} = SavedViews.save(@company, :shared, "Everyone", view())

    {:ok, reviewers} =
      SavedViews.save(@company, :shared, "Reviewers", view(), ["reviewer", "auditor"])

    assert SavedViews.roles(everyone) == []
    assert SavedViews.roles(reviewers) == ["reviewer", "auditor"]

    assert Enum.map(SavedViews.visible_shared(@company, "users", []), & &1["slug"]) == [
             "everyone"
           ]

    assert Enum.map(SavedViews.visible_shared(@company, "users", ["auditor"]), & &1["slug"]) ==
             ["everyone", "reviewers"]

    assert SavedViews.visible_shared(nil, "users", ["auditor"]) == []
    assert SavedViews.fetch(@own, @company, "users", "shared:reviewers", ["clerk"]) == :error

    assert {:ok, ^reviewers, :shared} =
             SavedViews.fetch(@own, @company, "users", "shared:reviewers", ["reviewer"])

    assert {:error, :roles} = SavedViews.save(@company, :shared, "Bad", view(), ["Not A Code"])

    # An own view never carries an audience.
    {:ok, own} = SavedViews.save(@own, :own, "Mine", view(), ["reviewer"])
    refute Map.has_key?(own, "roles")
  end
end
