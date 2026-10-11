defmodule Bilimbi.Base.AgentApi.SearchTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.AgentApi.ContributionValidator
  alias Bilimbi.Base.AgentApi.Search
  alias Bilimbi.Base.AgentApi.TestFixtures
  alias Bilimbi.Base.AgentApi.TestOperations

  setup do
    registry =
      ContributionValidator.validate_contributions!([
        %{descriptor: TestFixtures.descriptor(), payload: TestOperations.payload()}
      ])

    %{entries: Map.values(registry.operations) ++ Map.values(registry.guides)}
  end

  defp keys(ranked), do: Enum.map(ranked, fn {entry, _score} -> entry.key end)

  test "words are lowercased, split, stripped of filler and of simple endings" do
    assert Search.tokens("Find the Companies, listing ADDRESSES for me!") ==
             ~w(find company list address)

    assert Search.tokens("statuses boxes") == ~w(status box)
  end

  test "a word and its plural reach the same stem" do
    for {singular, plural} <- [
          {"setting", "settings"},
          {"listing", "listings"},
          {"building", "buildings"},
          {"cache", "caches"},
          {"house", "houses"},
          {"employee", "employees"},
          {"company", "companies"},
          {"address", "addresses"},
          {"status", "statuses"},
          {"box", "boxes"}
        ] do
      assert Search.tokens(singular) == Search.tokens(plural), "#{singular}/#{plural}"
    end
  end

  test "an operation about a singular -ing noun is found by its plural and back" do
    entry = %Bilimbi.Base.AgentApi.Guide{
      key: "base.example.value",
      owner: "base/example",
      capability: "admin.example.view",
      title: "Read a setting",
      summary: "Shows one value",
      keywords: [],
      body: ""
    }

    assert [{^entry, _score}] = Search.rank([entry], "settings")
    plural = %{entry | title: "Read settings"}
    assert [{^plural, _score}] = Search.rank([plural], "setting")
  end

  test "a keyword lifts the list above the read that shares its noun", %{entries: entries} do
    assert ["base.agent_api.record.list" | _rest] = keys(Search.rank(entries, "find records"))

    assert ["base.agent_api.record.get" | _rest] =
             keys(Search.rank(entries, "show record detail"))
  end

  test "a word only a guide's body holds still finds the guide", %{entries: entries} do
    assert keys(Search.rank(entries, "archived")) == ["base.agent_api.record"]
  end

  test "nothing matching gives nothing, and no words browse everything by key", %{
    entries: entries
  } do
    assert Search.rank(entries, "invoice") == []

    assert keys(Search.rank(entries, "  the  ")) ==
             ~w(base.agent_api.record base.agent_api.record.get base.agent_api.record.list
                base.agent_api.record.update)
  end

  test "equal scores fall to the key, so the order never changes between calls", %{
    entries: entries
  } do
    ranked = Search.rank(entries, "record")
    assert ranked == Search.rank(Enum.reverse(entries), "record")

    tied =
      ranked
      |> Enum.group_by(fn {_entry, score} -> score end, fn {entry, _score} -> entry.key end)
      |> Map.values()

    assert Enum.all?(tied, &(&1 == Enum.sort(&1)))
  end
end
