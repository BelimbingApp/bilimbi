defmodule Bilimbi.Base.PrincipalDirectoryContractTest do
  @moduledoc """
  The properties `rank/3` promises, checked on doubles.

  Base cannot reach Core, so the real providers are exercised in their own
  packages. What this file protects is the contract *as written* — an ordering,
  a composite identity and two failure modes whose only other enforcement is the
  honesty of each implementor. `company_directory_contract_test.exs` exists for
  the same reason and is the model.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.PrincipalDirectory
  alias Bilimbi.Base.PrincipalDirectory.TestAgentProvider
  alias Bilimbi.Base.PrincipalDirectory.TestUserProvider
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  @providers %{user: TestUserProvider, agent: TestAgentProvider}

  setup do
    %{scope: scope(), providers: @providers}
  end

  test "orders by the name displayed, case-insensitively", %{scope: scope, providers: p} do
    {:ok, ranked} =
      PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 2}, {:user, 3}], providers: p)

    assert Enum.map(ranked, & &1.name) == ["ada lovelace", "eMart Holdings", "Zulu Facility"]

    # Sorting raw binaries is codepoint order, which files every lowercase
    # initial after every uppercase one. The double names users in descending id
    # order precisely so both wrong answers fail here.
    refute Enum.map(ranked, & &1.name) == Enum.sort(Enum.map(ranked, & &1.name))
    refute Enum.map(ranked, & &1.id) == Enum.sort(Enum.map(ranked, & &1.id))
  end

  test "identity is the pair, so colliding ids do not overwrite", %{scope: scope, providers: p} do
    {:ok, ranked} = PrincipalDirectory.rank(scope, [{:user, 1}, {:agent, 1}], providers: p)

    assert length(ranked) == 2
    assert %{kind: :user, id: 1, name: "eMart Holdings"} in ranked
    assert %{kind: :agent, id: 1, name: "Delivery Bot"} in ranked
  end

  test "ties break on kind then id, deterministically", %{scope: scope, providers: p} do
    # Both are named "ada lovelace"; :agent sorts before :user.
    {:ok, ranked} = PrincipalDirectory.rank(scope, [{:user, 3}, {:agent, 3}], providers: p)

    assert Enum.map(ranked, &{&1.kind, &1.id}) == [{:agent, 3}, {:user, 3}]

    # Same answer whichever order the candidates arrive in -- a rank that
    # depended on input order would page differently on a reload.
    {:ok, reversed} = PrincipalDirectory.rank(scope, [{:agent, 3}, {:user, 3}], providers: p)
    assert reversed == ranked
  end

  test "an unresolvable principal is absent, not an error", %{scope: scope, providers: p} do
    {:ok, ranked} = PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 404}], providers: p)

    assert Enum.map(ranked, & &1.id) == [1]
  end

  test "a kind with no installed provider resolves to nothing without failing",
       %{scope: scope} do
    {:ok, ranked} =
      PrincipalDirectory.rank(scope, [{:user, 1}, {:agent, 1}],
        providers: %{user: TestUserProvider}
      )

    assert Enum.map(ranked, &{&1.kind, &1.id}) == [{:user, 1}]
  end

  test "over the ceiling is an error, not a truncation", %{scope: scope, providers: p} do
    assert {:error, :too_many_candidates} =
             PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 2}], providers: p, ceiling: 1)

    # A silently truncated ranking would look like a sort and would not be one.
    refute match?({:ok, _}, PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 2}],
             providers: p,
             ceiling: 1
           ))
  end

  test "search filters case-insensitively", %{scope: scope, providers: p} do
    {:ok, ranked} =
      PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 2}, {:user, 3}],
        providers: p,
        search: "  ADA  "
      )

    assert Enum.map(ranked, & &1.name) == ["ada lovelace"]
  end

  test "search refuses rather than degrading when a kind cannot be resolved",
       %{scope: scope} do
    assert {:error, :name_search_unavailable} =
             PrincipalDirectory.rank(scope, [{:user, 1}, {:agent, 1}],
               providers: %{user: TestUserProvider},
               search: "bot"
             )
  end

  test "a blank search is no search, not a search for nothing", %{scope: scope, providers: p} do
    {:ok, ranked} =
      PrincipalDirectory.rank(scope, [{:user, 1}, {:user, 2}], providers: p, search: "   ")

    assert length(ranked) == 2
  end

  defp scope do
    Scope.for_tenant(%Identity{
      id: 1,
      name: "Tenant 1",
      status: "active",
      is_platform_operator: false
    })
  end
end
