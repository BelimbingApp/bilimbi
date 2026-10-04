defmodule Bilimbi.Base.ModuleRegistry.PutConsumersForTestTest do
  # Installs into a VM-wide persistent term, so it cannot share a run window
  # with a test that reads the installed snapshot.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  test "names only the consumers a test exercises; every other one stays readable" do
    ContributionRegistry.put_consumers_for_test!(%{menu: [:item]}, "probe")

    assert %{graph_fingerprint: "probe"} = ContributionRegistry.snapshot!()
    assert ContributionRegistry.consumer!(:menu) == [:item]

    for consumer <- Map.keys(ContributionRegistry.build!([]).consumers), consumer != :menu do
      assert ContributionRegistry.consumer!(consumer) ==
               Map.fetch!(ContributionRegistry.build!([]).consumers, consumer)
    end
  end

  test "refuses a consumer key the registry does not know" do
    assert_raise ArgumentError, ~r/unknown test consumers: \[:bogus\]/, fn ->
      ContributionRegistry.put_consumers_for_test!(%{bogus: []})
    end
  end
end
