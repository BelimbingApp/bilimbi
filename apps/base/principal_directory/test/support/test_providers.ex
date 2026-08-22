defmodule Bilimbi.Base.PrincipalDirectory.TestUserProvider do
  @moduledoc """
  A conforming user provider.

  Names are returned in **descending id order** and with mixed capitalisation on
  purpose: the contract promises ordering by normalised display name, and a
  double that happened to be sorted by id or by raw binary would let a broken
  implementation pass.

  User 404 is deliberately unresolvable — the scope cannot see it — because
  absence is part of the contract, not an error.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  @names %{
    3 => "ada lovelace",
    2 => "Zulu Facility",
    1 => "eMart Holdings"
  }
  @email_matches %{"billing@example.test" => [1]}

  @impl true
  def principal_kind, do: :user

  @impl true
  def names(_scope, ids), do: Map.take(@names, ids)

  @impl true
  def search(_scope, ids, term),
    do: @email_matches |> Map.get(term, []) |> Enum.filter(&(&1 in ids))

  @impl true
  def candidate_ids(_scope, :billing_contacts), do: [3, 1]

  def candidate_ids(_scope, _selection), do: []
end

defmodule Bilimbi.Base.PrincipalDirectory.TestAgentProvider do
  @moduledoc """
  A conforming agent provider whose ids deliberately collide with the user
  provider's. If identity were keyed on the id alone, these would overwrite each
  other.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  @names %{
    1 => "Delivery Bot",
    3 => "ada lovelace"
  }

  @impl true
  def principal_kind, do: :agent

  @impl true
  def names(_scope, ids), do: Map.take(@names, ids)
end
