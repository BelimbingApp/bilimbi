defmodule Bilimbi.Core.Employee.PrincipalDirectoryContributionTest do
  @moduledoc """
  Core Employee contributes two directory providers now — `:agent` and
  `:employee` (ADR 0014) — through the list form of the `principal_directory`
  contribution. This proves the real contribution validates into one provider
  per kind, and that a kind claimed twice is still refused.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.PrincipalDirectory.ContributionValidator
  alias Bilimbi.Core.Employee.Contributions
  alias Bilimbi.Core.Employee.EmployeeDirectoryProvider
  alias Bilimbi.Core.Employee.PrincipalDirectoryProvider

  defp descriptor, do: %{id: "core/employee", otp_app: :bilimbi_core_employee}

  test "the contribution is the two providers, one per kind" do
    payload = Contributions.contributions()[:principal_directory]
    assert payload == [PrincipalDirectoryProvider, EmployeeDirectoryProvider]

    assert ContributionValidator.validate_contributions!([
             %{descriptor: descriptor(), payload: payload}
           ]) ==
             %{agent: PrincipalDirectoryProvider, employee: EmployeeDirectoryProvider}
  end

  test "a kind claimed twice, even within one module's list, is a defect" do
    entry = %{
      descriptor: descriptor(),
      payload: [EmployeeDirectoryProvider, EmployeeDirectoryProvider]
    }

    assert_raise ArgumentError, ~r/already claimed/, fn ->
      ContributionValidator.validate_contributions!([entry])
    end
  end

  test "a list entry that is not a module atom is refused" do
    entry = %{descriptor: descriptor(), payload: [PrincipalDirectoryProvider, "nope"]}

    assert_raise ArgumentError, ~r/list entries must be module atoms/, fn ->
      ContributionValidator.validate_contributions!([entry])
    end
  end
end
