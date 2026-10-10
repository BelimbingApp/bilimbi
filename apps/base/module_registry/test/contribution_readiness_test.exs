defmodule Bilimbi.Base.ModuleRegistry.ContributionReadinessTest do
  # Installs into a VM-wide persistent term, so it cannot share a run window
  # with a test that reads the installed snapshot.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    ContributionRegistry.clear_for_test!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  test "a subscriber learns of the installation it was started before" do
    refute ContributionRegistry.installed?()
    assert :ok = ContributionRegistry.subscribe_installed()
    refute_received {ContributionRegistry, :installed}

    ContributionRegistry.put_consumers_for_test!(%{}, "readiness")

    assert ContributionRegistry.installed?()
    assert_receive {ContributionRegistry, :installed}
  end

  test "an installed snapshot is reported by installed?/0, not by a message" do
    ContributionRegistry.put_consumers_for_test!(%{}, "readiness")

    assert :ok = ContributionRegistry.subscribe_installed()
    assert ContributionRegistry.installed?()
    refute_receive {ContributionRegistry, :installed}, 50
  end

  test "an unsubscribed process receives nothing" do
    ContributionRegistry.put_consumers_for_test!(%{}, "readiness")
    refute_receive {ContributionRegistry, :installed}, 50
  end
end
