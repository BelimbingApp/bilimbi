defmodule Bilimbi.Base.Authz.EffectivePermissions do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.Repo

  defstruct direct_denies: MapSet.new(),
            direct_allows: MapSet.new(),
            role_grants: MapSet.new(),
            grant_all: false

  @type t :: %__MODULE__{}

  @spec load(Actor.t(), module()) :: t()
  def load(%Actor{} = actor, company_directory) do
    {direct_denies, direct_allows} = direct_grants(actor)
    {role_ids, grant_all} = assigned_roles(actor, company_directory)

    role_grants =
      if grant_all or role_ids == [] do
        MapSet.new()
      else
        from(grant in RoleCapability,
          where: grant.role_id in ^role_ids,
          select: grant.capability_key,
          distinct: true
        )
        |> Repo.all()
        |> MapSet.new()
      end

    %__MODULE__{
      direct_denies: direct_denies,
      direct_allows: direct_allows,
      role_grants: role_grants,
      grant_all: grant_all
    }
  end

  @spec evaluate(t(), String.t(), [String.t()]) :: Decision.t()
  def evaluate(%__MODULE__{} = permissions, capability, policies) do
    cond do
      MapSet.member?(permissions.direct_denies, capability) ->
        Decision.deny(:denied_explicitly, policies ++ ["direct_capability"])

      MapSet.member?(permissions.direct_allows, capability) ->
        Decision.allow(policies ++ ["direct_capability"])

      permissions.grant_all ->
        Decision.allow(policies ++ ["grant_all"])

      MapSet.member?(permissions.role_grants, capability) ->
        Decision.allow(policies ++ ["role_capability"])

      true ->
        Decision.deny(:denied_missing_capability, policies ++ ["role_capability"])
    end
  end

  @spec allowed(t(), [String.t()]) :: [String.t()]
  def allowed(%__MODULE__{} = permissions, known_capabilities) do
    candidates =
      if permissions.grant_all do
        MapSet.new(known_capabilities)
      else
        MapSet.union(permissions.direct_allows, permissions.role_grants)
      end

    candidates
    |> MapSet.intersection(MapSet.new(known_capabilities))
    |> MapSet.difference(permissions.direct_denies)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @spec denied(t()) :: [String.t()]
  def denied(%__MODULE__{} = permissions) do
    permissions.direct_denies |> MapSet.to_list() |> Enum.sort()
  end

  defp direct_grants(actor) do
    rows =
      from(grant in PrincipalCapability,
        where:
          grant.principal_type == ^Actor.principal_type(actor) and
            grant.principal_id == ^actor.id,
        where: grant.company_id == ^actor.company_id or is_nil(grant.company_id),
        select: {grant.capability_key, grant.is_allowed}
      )
      |> Repo.all()

    Enum.reduce(rows, {MapSet.new(), MapSet.new()}, fn
      {key, false}, {denies, allows} -> {MapSet.put(denies, key), allows}
      {key, true}, {denies, allows} -> {denies, MapSet.put(allows, key)}
    end)
  end

  defp assigned_roles(actor, company_directory) do
    company_ids = company_directory.company_ids(actor.scope)

    rows =
      from(assignment in PrincipalRole,
        join: role in Role,
        on: role.id == assignment.role_id,
        where:
          assignment.principal_type == ^Actor.principal_type(actor) and
            assignment.principal_id == ^actor.id,
        where:
          (role.is_system and is_nil(role.company_id) and
             (assignment.company_id == ^actor.company_id or is_nil(assignment.company_id))) or
            (not role.is_system and role.company_id in ^company_ids and
               assignment.company_id == ^actor.company_id),
        select: {role.id, role.grant_all},
        distinct: true
      )
      |> Repo.all()

    {Enum.map(rows, &elem(&1, 0)), Enum.any?(rows, &elem(&1, 1))}
  end
end
