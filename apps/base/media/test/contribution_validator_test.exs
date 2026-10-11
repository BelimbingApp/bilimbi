defmodule Bilimbi.Base.Media.ContributionValidatorTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.Media.{ContributionValidator, TestAuthorizer, TestFixtures}

  test "empty registry and descriptor-owned policies including legacy aliases" do
    assert ContributionValidator.validate_contributions!([]) == %{}
    registry = ContributionValidator.validate_contributions!([TestFixtures.entry()])

    assert %{adapter: TestAuthorizer, key: "test.record", owner: "domain/test"} =
             registry["App\\Domain\\Test\\Record"]

    assert registry["test.record"] == registry["App\\Domain\\Test\\Record"]
  end

  test "duplicate stable keys or aliases fail independent of install order" do
    entry = TestFixtures.entry()

    assert_raise ArgumentError, ~r/duplicate subject/, fn ->
      ContributionValidator.validate_contributions!([entry, entry])
    end

    entry =
      put_in(entry.payload.subjects, [
        %{key: "other.record", adapter: TestAuthorizer, aliases: ["test.record"]}
      ])

    assert_raise ArgumentError, ~r/duplicate subject/, fn ->
      ContributionValidator.validate_contributions!([TestFixtures.entry(), entry])
    end
  end

  test "missing dependency, foreign adapters and unknown payload fields fail closed" do
    entry = TestFixtures.entry()

    for bad <- [
          put_in(entry.descriptor.dependencies, []),
          put_in(entry.descriptor.otp_app, :bilimbi_base_database),
          %{entry | payload: %{subjects: [], unknown: []}}
        ] do
      assert_raise ArgumentError, fn -> ContributionValidator.validate_contributions!([bad]) end
    end

    for adapter <- [String, nil, false, Bilimbi.Base.Media.ULID] do
      bad = put_in(entry.payload.subjects, [%{key: "test.record", adapter: adapter}])
      assert_raise ArgumentError, fn -> ContributionValidator.validate_contributions!([bad]) end
    end
  end
end
