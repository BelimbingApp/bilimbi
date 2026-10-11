defmodule Bilimbi.Base.Grid.PageViewsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Grid.PageViews
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures

  @own Scope.user(91, 73, 41)
  @other Scope.user(92, 73, 41)

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

  defp view(table, overrides \\ %{}) do
    struct!(
      %View{
        table: table,
        columns: ~w(name company.name employees:count),
        lenses: %{"employees:count" => "bar"},
        zoom: 22,
        since: ~D[2026-08-01]
      },
      overrides
    )
  end

  test "an account starts with nothing arranged" do
    assert PageViews.fetch(@own, "users") == :error
  end

  test "an arrangement is kept per account and per page, and read back whole" do
    assert :ok = PageViews.remember(@own, view("users"))

    assert :ok =
             PageViews.remember(@own, view("companies", %{columns: ~w(name), zoom: 36}))

    assert PageViews.fetch(@own, "users") == {:ok, view("users")}

    assert PageViews.fetch(@own, "companies") ==
             {:ok, view("companies", %{columns: ~w(name), zoom: 36})}

    # Another account of the same company arranged nothing.
    assert PageViews.fetch(@other, "users") == :error
  end

  test "arranging a page again replaces what was kept for it and leaves the others" do
    :ok = PageViews.remember(@own, view("users"))
    :ok = PageViews.remember(@own, view("companies"))
    :ok = PageViews.remember(@own, view("users", %{columns: ~w(email), lenses: %{}}))

    assert {:ok, %View{columns: ["email"], lenses: lenses}} = PageViews.fetch(@own, "users")
    assert lenses == %{}
    assert PageViews.fetch(@own, "companies") == {:ok, view("companies")}
    assert length(Settings.get(PageViews.key(), @own)) == 2
  end

  test "going back to the page's own columns forgets the page" do
    :ok = PageViews.remember(@own, view("users"))
    :ok = PageViews.remember(@own, %View{table: "users"})

    assert PageViews.fetch(@own, "users") == :error
    assert Settings.get(PageViews.key(), @own) == []
  end

  test "an arrangement equal to the one kept writes nothing" do
    AuditFixtures.create_audit_tables!()
    :ok = PageViews.remember(@own, view("users"))
    written = Repo.aggregate("base_audit_mutations", :count)
    assert written > 0

    assert :ok = PageViews.remember(@own, view("users"))
    assert :ok = PageViews.remember(@own, %View{table: "companies"})
    assert Repo.aggregate("base_audit_mutations", :count) == written
  end

  test "an entry that is not a page and a view is ignored rather than raised on" do
    {:ok, _stored} =
      Settings.put(
        PageViews.key(),
        [
          %{"page" => "users"},
          "nonsense",
          %{"page" => "companies", "view" => %{"zoom" => "x"}}
        ],
        @own
      )

    assert PageViews.fetch(@own, "users") == :error
    assert PageViews.fetch(@own, "companies") == {:ok, %View{table: "companies"}}
  end
end
