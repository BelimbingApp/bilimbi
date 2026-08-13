defmodule Bilimbi.Base.ModuleRegistry.ContributionRegistryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  test "builds a deterministic empty consumer snapshot from a valid provider" do
    assert %{
             graph_fingerprint: "test-fingerprint",
             consumers: %{settings: [], authz: [], menu: []}
           } = ContributionRegistry.build!([descriptor(Bilimbi.Base.ModuleRegistry.TestProvider)])
  end

  test "rejects unknown consumers with provider provenance" do
    assert_raise ArgumentError,
                 ~r/UnknownConsumerTestProvider.*tests\/provider.*unknown keys/s,
                 fn ->
                   ContributionRegistry.build!([
                     descriptor(Bilimbi.Base.ModuleRegistry.UnknownConsumerTestProvider)
                   ])
                 end
  end

  test "rejects non-plain provider payloads" do
    assert_raise ArgumentError, ~r/NonPlainTestProvider.*non-plain term/s, fn ->
      ContributionRegistry.build!([descriptor(Bilimbi.Base.ModuleRegistry.NonPlainTestProvider)])
    end
  end

  test "wraps provider failures with provenance" do
    assert_raise ArgumentError, ~r/ThrowingTestProvider.*tests\/provider.*provider failed/s, fn ->
      ContributionRegistry.build!([descriptor(Bilimbi.Base.ModuleRegistry.ThrowingTestProvider)])
    end
  end

  test "requires the contribution provider behaviour" do
    assert_raise ArgumentError, ~r/MissingBehaviourTestProvider.*must implement/s, fn ->
      ContributionRegistry.build!([
        descriptor(Bilimbi.Base.ModuleRegistry.MissingBehaviourTestProvider)
      ])
    end
  end

  defp descriptor(provider) do
    %{
      id: "tests/provider",
      otp_app: :bilimbi_base_module_registry,
      contribution_provider: provider,
      graph_fingerprint: "test-fingerprint"
    }
  end
end
