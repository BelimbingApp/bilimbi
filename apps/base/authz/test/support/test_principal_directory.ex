defmodule Bilimbi.Base.Authz.TestUserDirectory do
  @moduledoc """
  A user-naming double that answers only inside tenant 1.

  Names are written in **descending id order** with mixed capitalisation, so a
  screen that ordered by id, or that sorted raw binaries and filed every
  lowercase initial after every uppercase one, would fail rather than pass by
  luck.

  User 7 is named and user 88 is not, which is what makes the "a principal the
  directory cannot resolve keeps its id" assertions mean something: both ids
  reach the provider, and only one comes back.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  alias Bilimbi.Base.Tenancy.Scope

  @names %{
    9 => "ada lovelace",
    7 => "Zulu Facility",
    5 => "eMart Holdings"
  }

  @impl true
  def principal_kind, do: :user

  @impl true
  def names(scope, ids) do
    if Scope.tenant_id(scope) == 1, do: Map.take(@names, ids), else: %{}
  end
end

defmodule Bilimbi.Base.Authz.TestAgentDirectory do
  @moduledoc """
  An agent-naming double whose ids collide with the user double's.

  Agent 7 and user 7 are different principals with different names. If a screen
  keyed its name lookup on the id alone, one would wear the other's name.
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  alias Bilimbi.Base.Tenancy.Scope

  @names %{7 => "Delivery Bot", 5 => "midnight sweeper"}

  @impl true
  def principal_kind, do: :agent

  @impl true
  def names(scope, ids) do
    if Scope.tenant_id(scope) == 1, do: Map.take(@names, ids), else: %{}
  end
end
