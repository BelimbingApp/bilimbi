defmodule Bilimbi.Base.Tenancy.ActorVerifierContributionTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Tenancy.ActorVerifier.ContributionValidator

  defmodule Verifier do
    @behaviour Bilimbi.Base.Tenancy.ActorVerifier

    @impl true
    def verify_actor(_scope), do: :ok
  end

  test "no contribution installs no verifier" do
    assert ContributionValidator.validate_contributions!([]) == nil
  end

  test "two verifiers are a defect, whatever the installation order" do
    assert_raise ArgumentError, ~r/more than one verifier from core\/a, core\/b/, fn ->
      ContributionValidator.validate_contributions!([
        entry("core/a", Verifier),
        entry("core/b", Verifier)
      ])
    end
  end

  test "a verifier must implement the behaviour and belong to its contributor" do
    assert_raise ArgumentError, ~r/does not implement/, fn ->
      ContributionValidator.validate_contributions!([entry("core/a", Enum)])
    end

    assert_raise ArgumentError, ~r/does not belong to :bilimbi_base_tenancy/, fn ->
      ContributionValidator.validate_contributions!([entry("core/a", Verifier)])
    end
  end

  defp entry(id, verifier),
    do: %{descriptor: %{id: id, otp_app: :bilimbi_base_tenancy}, payload: verifier}
end
