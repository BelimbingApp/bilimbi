defmodule Bilimbi.Base.PrincipalDirectory.Provider do
  @moduledoc """
  What a Core module implements so Base screens can name its principals.

  One provider per principal kind. A provider answers only for its own kind and
  only inside the scope it is given; it never orders or decides what a screen
  shows for a principal it cannot resolve. Those belong to
  `Bilimbi.Base.PrincipalDirectory`, so that ordering is consistent across kinds
  and a screen mixing users and agents interleaves them by name rather than
  listing one kind after the other.

  Resolution is deliberately *partial*: an id the provider cannot see — deleted,
  archived, or belonging to another tenant — is simply absent from the returned
  map. Absence is not an error. ADR 0011 requires the row to survive and show its
  durable type and id, which is only possible if the provider reports "no name"
  rather than raising.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @typedoc """
  The kinds of identity a screen references and cannot name itself. `:user` and
  `:agent` are the authz-principal subset Base Authz stores in
  `principal_capabilities`; `:employee` is a Core identity named on Core screens
  (an employee referenced by id across an upward edge — a department Head, a
  supervisor). See ADR 0014; the seam names referenced identities, of which
  principals are the subset.
  """
  @type kind :: :user | :agent | :employee

  @doc "The one kind this provider answers for."
  @callback principal_kind() :: kind()

  @doc """
  Names the ids this provider can see inside `scope`.

  Keys are ids of `principal_kind/0`. Ids the scope cannot see are omitted, not
  reported — see the moduledoc. Implementations must be tenant-scoped by
  construction rather than by filtering afterwards.
  """
  @callback names(Scope.t(), [pos_integer()]) :: %{pos_integer() => String.t()}

  @doc """
  Returns the IDs eligible for a provider-owned picker selection.

  `selection` is deliberately opaque to Base. The provider owns both the
  vocabulary and the containment check: for example, the employee provider can
  answer the employees currently belonging to one company without making a
  Core Company consumer depend on Core Employee. Consumers must ask again when
  they persist a submitted ID; a rendered select is not an authorization
  boundary.
  """
  @callback candidate_ids(Scope.t(), selection :: term()) :: [pos_integer()]

  @doc """
  Returns candidate ids matching a provider-owned search attribute.

  The candidate list is supplied by the Base-owned screen, so this callback
  must only return ids from it and only from within `scope`. It lets a provider
  search attributes such as an account email without exposing that attribute in
  a Base contract. Name matching remains owned by `PrincipalDirectory`.
  """
  @callback search(Scope.t(), [pos_integer()], String.t()) :: [pos_integer()]

  @optional_callbacks search: 3, candidate_ids: 2
end
