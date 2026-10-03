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
    from_roles(actor, assigned_roles(actor, company_directory))
  end

  @doc """
  Builds permissions after the caller has already proved `company_id` live.

  `can` fetches that company once, together with the role ids, and passes both
  in. This does not query `companies` again.
  """
  @spec load(Actor.t(), module(), pos_integer(), {role_ids(), boolean()}) :: t()
  def load(%Actor{} = actor, _company_directory, company_id, {role_ids, grant_all})
      when is_integer(company_id) and company_id > 0 and is_list(role_ids) and
             is_boolean(grant_all) do
    from_roles(actor, {role_ids, grant_all})
  end

  @doc """
  Proves the actor's company is live and returns the role ids in that same read.

  `:out_of_scope` means the company is missing, archived, or in another tenant,
  which is `can`'s invalid-actor denial. A directory without
  `live_company_ids_query/1` answers from its id callbacks instead of SQL.
  """
  @spec live_company_roles(Actor.t(), module()) ::
          :out_of_scope | {:ok, pos_integer(), {role_ids(), boolean()}}
  def live_company_roles(%Actor{} = actor, company_directory) do
    if live_company_query?(company_directory) do
      live_company_roles_query(actor, company_directory)
    else
      live_company_roles_list(actor, company_directory)
    end
  end

  @typep role_ids :: [pos_integer()]

  defp from_roles(actor, {role_ids, grant_all}) do
    {direct_denies, direct_allows} = direct_grants(actor)

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

  @spec explicitly_allowed?(Actor.t(), String.t(), module()) :: boolean()
  def explicitly_allowed?(%Actor{} = actor, capability, company_directory)
      when is_binary(capability) do
    {denies, allows} = direct_grants(actor)

    cond do
      MapSet.member?(denies, capability) -> false
      MapSet.member?(allows, capability) -> true
      true -> role_granted?(actor, capability, company_directory)
    end
  end

  defp role_granted?(actor, capability, company_directory) do
    case assigned_roles(actor, company_directory) do
      {[], _grant_all} ->
        false

      {role_ids, _grant_all} ->
        from(grant in RoleCapability,
          where: grant.role_id in ^role_ids and grant.capability_key == ^capability
        )
        |> Repo.exists?()
    end
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
    rows =
      if live_company_query?(company_directory) do
        role_rows_in(actor, company_directory.live_company_ids_query(actor.scope))
      else
        role_rows_among(actor, company_directory.company_ids(actor.scope))
      end

    {Enum.map(rows, &elem(&1, 0)), Enum.any?(rows, &elem(&1, 1))}
  end

  defp live_company_roles_list(actor, company_directory) do
    if company_directory.company_in_scope?(actor.scope, actor.company_id) do
      {:ok, actor.company_id, assigned_roles(actor, company_directory)}
    else
      :out_of_scope
    end
  end

  # One statement: the actor's live company row, with matching roles beside it.
  # An empty result is "not in scope", distinct from "in scope, no roles", which
  # is one row whose role id is null. Custom roles may belong to any live
  # company in the tenant; the assignment itself stays on the actor's company.
  defp live_company_roles_query(actor, company_directory) do
    live = company_directory.live_company_ids_query(actor.scope)
    actor_live = where(live, [company], company.id == ^actor.company_id)
    type = Actor.principal_type(actor)

    matching_roles =
      from(assignment in PrincipalRole,
        join: role in Role,
        on: role.id == assignment.role_id,
        where:
          assignment.principal_type == ^type and
            assignment.principal_id == ^actor.id and
            ((role.is_system and is_nil(role.company_id) and
                (assignment.company_id == ^actor.company_id or is_nil(assignment.company_id))) or
               (not role.is_system and
                  role.company_id in subquery(
                    company_directory.live_company_ids_query(actor.scope)
                  ) and
                  assignment.company_id == ^actor.company_id)),
        distinct: true,
        select: %{role_id: role.id, grant_all: role.grant_all}
      )

    rows =
      from(company in subquery(actor_live),
        left_join: matched in subquery(matching_roles),
        on: true,
        select: {company.id, matched.role_id, matched.grant_all}
      )
      |> Repo.all()

    case rows do
      [] ->
        :out_of_scope

      [{company_id, _role_id, _grant_all} | _] = rows ->
        role_rows =
          for {_company_id, role_id, grant_all} <- rows,
              is_integer(role_id),
              do: {role_id, grant_all}

        {:ok, company_id,
         {Enum.uniq(Enum.map(role_rows, &elem(&1, 0))), Enum.any?(role_rows, &elem(&1, 1))}}
    end
  end

  # The two queries below are the same rule. A dynamic cannot sit inside the
  # `or`, so the company-id comparison is written out twice: once for a list
  # and once for the live-id subquery.
  defp role_rows_among(actor, company_ids) do
    role_assignment_query(actor)
    |> where(
      [assignment, role],
      (role.is_system and is_nil(role.company_id) and
         (assignment.company_id == ^actor.company_id or is_nil(assignment.company_id))) or
        (not role.is_system and role.company_id in ^company_ids and
           assignment.company_id == ^actor.company_id)
    )
    |> Repo.all()
  end

  defp role_rows_in(actor, company_query) do
    role_assignment_query(actor)
    |> where(
      [assignment, role],
      (role.is_system and is_nil(role.company_id) and
         (assignment.company_id == ^actor.company_id or is_nil(assignment.company_id))) or
        (not role.is_system and role.company_id in subquery(company_query) and
           assignment.company_id == ^actor.company_id)
    )
    |> Repo.all()
  end

  defp role_assignment_query(actor) do
    from(assignment in PrincipalRole,
      join: role in Role,
      on: role.id == assignment.role_id,
      where:
        assignment.principal_type == ^Actor.principal_type(actor) and
          assignment.principal_id == ^actor.id,
      distinct: true,
      select: {role.id, role.grant_all}
    )
  end

  defp live_company_query?(company_directory) do
    Code.ensure_loaded?(company_directory) and
      function_exported?(company_directory, :live_company_ids_query, 1)
  end
end
