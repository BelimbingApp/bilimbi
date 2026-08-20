defmodule Bilimbi.Core.User.PrincipalDirectoryProvider do
  @moduledoc """
  Names `:user` principals for Base screens, without Base querying Core.

  The seam is specified in ADR 0011. Base owns sessions, grants and assignments;
  this answers the one question Base cannot: what is this person called.

  Tenant scoping is not a filter applied afterwards — it is
  `Core.User.get_tenant_users/2`, which resolves the scope's companies first and
  restricts to them in the query. A user outside the actor's tenant is therefore
  never read, let alone returned, and the caller keeps the row with its durable
  type and id (#285).
  """

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.User

  @impl true
  def principal_kind, do: :user

  @doc """
  Names the users the scope can see, omitting the rest.

  Deliberately no `rescue`: `get_tenant_users/2` answers `{:ok, map}` for every
  business outcome, so a raise here means the database is unreachable or the
  schema is missing. Turning that into an empty map would render a screen full
  of ids and report nothing — the failure mode #359 shipped.
  """
  @impl true
  def names(%Scope{} = scope, ids) when is_list(ids) do
    {:ok, users} = User.get_tenant_users(scope, ids)

    Map.new(users, fn {id, summary} -> {id, summary.name} end)
  end
end
