defmodule Bilimbi.Base.Workflow.ContributionValidatorTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.Workflow.{ContributionValidator, TestContributions, TestFixtures}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  test "snapshot consumes definitions with owner provenance" do
    snapshot = ContributionRegistry.build!([TestFixtures.entry().descriptor])
    assert snapshot.consumers.workflow.subjects["example.record"].owner == "domain/example"
    assert snapshot.consumers.workflow.flows["example_flow"].subject == "example.record"

    assert snapshot.consumers.workflow.aliases[{:guards, "Legacy\\Example\\Guard"}] ==
             "example.guard"
  end

  test "duplicates fail independent of install order" do
    entry = TestFixtures.entry()

    assert_raise ArgumentError, ~r/duplicate subjects key/, fn ->
      ContributionValidator.validate_contributions!([entry, entry])
    end

    subject = hd(entry.payload.subjects)
    bad = put_in(entry.payload.subjects, [%{subject | aliases: ["example.record"]}])

    assert_raise ArgumentError, ~r/duplicate subjects alias/, fn ->
      ContributionValidator.validate_contributions!([bad])
    end
  end

  test "adapter ownership, declared dependency and behaviour are mandatory" do
    entry = TestFixtures.entry()
    bad = put_in(entry.descriptor.otp_app, :bilimbi_base_tenancy)

    assert_raise ArgumentError, ~r/does not belong/, fn ->
      ContributionValidator.validate_contributions!([bad])
    end

    bad = put_in(entry.descriptor.dependencies, [])

    assert_raise ArgumentError, ~r/must declare base\/workflow/, fn ->
      ContributionValidator.validate_contributions!([bad])
    end

    subject = hd(entry.payload.subjects)
    bad = put_in(entry.payload.subjects, [%{subject | adapter: TestContributions}])

    assert_raise ArgumentError, ~r/must implement/, fn ->
      ContributionValidator.validate_contributions!([bad])
    end
  end

  test "stored classes cannot be new keys and unknown references fail" do
    entry = TestFixtures.entry()
    [flow] = entry.payload.flows
    bad = put_in(entry.payload.flows, [%{flow | code: "Legacy\\Flow"}])

    assert_raise ArgumentError, ~r/stable public key/, fn ->
      ContributionValidator.validate_contributions!([bad])
    end

    [edge | rest] = flow.transitions

    for edge <- [%{edge | to: "absent"}, %{edge | guard: "absent.guard"}] do
      bad = put_in(entry.payload.flows, [%{flow | transitions: [edge | rest]}])
      assert_raise ArgumentError, fn -> ContributionValidator.validate_contributions!([bad]) end
    end
  end
end
