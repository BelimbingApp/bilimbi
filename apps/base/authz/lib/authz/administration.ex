defmodule Bilimbi.Base.Authz.Administration do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.Authz.CapabilitySummary
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.DecisionLogSummary
  alias Bilimbi.Base.Authz.Page
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalCapabilitySummary
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.PrincipalRoleSummary
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.Authz.RoleSummary
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  @default_page_size 25
  @maximum_page_size 100
  @capability_sort_fields %{
    key: :key,
    domain: :domain,
    resource: :resource,
    action: :action,
    module: :module
  }
  @role_sort_fields %{
    name: :name,
    code: :code,
    is_system: :is_system,
    created_at: :created_at
  }
  @decision_log_sort_fields %{
    occurred_at: :occurred_at,
    capability: :capability,
    allowed: :allowed,
    reason: :reason_code,
    resource: :resource_type,
    actor_type: :actor_type,
    actor_id: :actor_id
  }
  @principal_capability_sort_fields %{
    created_at: :created_at,
    principal_type: :principal_type,
    principal_id: :principal_id,
    capability: :capability_key,
    allowed: :is_allowed,
    company_id: :company_id,
    company_name: :company_name
  }

  @spec list_capabilities(keyword(), map()) :: Page.t(CapabilitySummary.t())
  def list_capabilities(opts, registry) when is_list(opts) and is_map(registry) do
    opts =
      page_options!(opts,
        search: nil,
        domain: nil,
        sort_by: :key,
        sort_dir: :asc
      )

    search = search!(opts[:search])
    domain = domain_filter!(opts[:domain])
    sort_by = sort_by!(opts[:sort_by], @capability_sort_fields)
    sort_dir = sort_dir!(opts[:sort_dir])
    page = page!(opts[:page])
    page_size = page_size!(opts[:page_size])

    owners = Map.get(registry, :capability_owners, %{})
    capabilities = Map.get(registry, :capabilities, [])

    items =
      capabilities
      |> Enum.map(fn key ->
        parts = CapabilityKey.parse!(key)
        owner = Map.get(owners, key)

        %CapabilitySummary{
          id: key,
          key: key,
          domain: parts.domain,
          resource: parts.resource,
          action: parts.action,
          module: humanize_module(owner)
        }
      end)
      |> maybe_search_capabilities(search)
      |> maybe_filter_capability_domain(domain)
      |> sort_capabilities(sort_by, sort_dir)

    total_entries = length(items)
    total_pages = total_pages(total_entries, page_size)
    entries = Enum.slice(items, (page - 1) * page_size, page_size)

    %Page{
      entries: entries,
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @spec capability_domains(map()) :: [String.t()]
  def capability_domains(registry) when is_map(registry) do
    Map.get(registry, :capabilities, [])
    |> Enum.map(fn key -> CapabilityKey.parse!(key).domain end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec list_roles(Scope.t(), keyword(), map()) :: Page.t(RoleSummary.t())
  def list_roles(%Scope{} = scope, opts, registry) when is_list(opts) do
    opts =
      page_options!(opts,
        search: nil,
        sort_by: :name,
        sort_dir: :asc
      )

    company_ids = company_ids(scope, registry)
    visibility = company_visibility(scope, company_ids)

    query =
      company_ids
      |> scoped_roles()
      |> maybe_search_roles(search!(opts[:search]))

    page_query(
      query,
      order_query(query, sort_by!(opts[:sort_by], @role_sort_fields), opts, @role_sort_fields),
      opts,
      &role_summaries(&1, visibility)
    )
  end

  @spec list_decision_logs(Scope.t(), keyword(), map()) :: Page.t(DecisionLogSummary.t())
  def list_decision_logs(%Scope{} = scope, opts, registry) when is_list(opts) do
    opts =
      page_options!(opts,
        search: nil,
        allowed: nil,
        sort_by: :occurred_at,
        sort_dir: :desc
      )

    visibility = company_visibility(scope, company_ids(scope, registry))

    query =
      from(log in DecisionLog, where: ^visibility)
      |> maybe_search_decision_logs(search!(opts[:search]))
      |> maybe_filter_allowed(allowed!(opts[:allowed]))

    page_query(
      query,
      order_query(
        query,
        sort_by!(opts[:sort_by], @decision_log_sort_fields),
        opts,
        @decision_log_sort_fields
      ),
      opts,
      fn rows -> Enum.map(rows, &DecisionLogSummary.from_schema/1) end
    )
  end

  @spec list_principal_capabilities(Scope.t(), keyword(), map()) ::
          Page.t(PrincipalCapabilitySummary.t())
  def list_principal_capabilities(%Scope{} = scope, opts, registry) when is_list(opts) do
    opts =
      page_options!(opts,
        search: nil,
        allowed: nil,
        principal_type: nil,
        principal_id: nil,
        sort_by: :created_at,
        sort_dir: :desc,
        company_order: []
      )

    visibility = company_visibility(scope, company_ids(scope, registry))

    query =
      from(grant in PrincipalCapability, where: ^visibility)
      |> maybe_search_principal_capabilities(search!(opts[:search]))
      |> maybe_filter_principal_allowed(allowed!(opts[:allowed]))
      |> filter_principal(principal_filter!(opts[:principal_type], opts[:principal_id]))

    page_query(
      query,
      order_query(
        query,
        sort_by!(opts[:sort_by], @principal_capability_sort_fields),
        opts,
        @principal_capability_sort_fields
      ),
      opts,
      fn rows -> Enum.map(rows, &PrincipalCapabilitySummary.from_schema/1) end
    )
  end

  @principal_role_sort_fields %{
    created_at: :created_at,
    principal_type: :principal_type,
    principal_id: :principal_id,
    role_name: :role_name,
    company_id: :company_id,
    company_name: :company_name
  }

  @spec list_principal_roles(Scope.t(), keyword(), map()) :: Page.t(PrincipalRoleSummary.t())
  def list_principal_roles(%Scope{} = scope, opts, registry) when is_list(opts) do
    opts =
      page_options!(opts,
        search: nil,
        sort_by: :created_at,
        sort_dir: :desc,
        company_order: []
      )

    visibility = company_visibility(scope, company_ids(scope, registry))
    sort_by = sort_by!(opts[:sort_by], @principal_role_sort_fields)

    query =
      from(assignment in PrincipalRole,
        join: role in Role,
        on: role.id == assignment.role_id,
        where: ^visibility
      )
      |> maybe_search_principal_roles(search!(opts[:search]))

    ordered_query =
      query
      |> order_principal_roles(sort_by, opts)
      |> select([assignment, role], %{assignment: assignment, role: role})

    page_query(
      query,
      ordered_query,
      opts,
      fn rows ->
        Enum.map(rows, fn %{assignment: assignment, role: role} ->
          PrincipalRoleSummary.from_schema(assignment, role)
        end)
      end
    )
  end

  @spec list_principal_role_assignments(
          Scope.t(),
          :user | :agent,
          pos_integer(),
          keyword(),
          map()
        ) :: Page.t(PrincipalRoleSummary.t())
  def list_principal_role_assignments(
        %Scope{} = scope,
        principal_type,
        principal_id,
        opts,
        registry
      )
      when is_list(opts) do
    {principal_type, principal_id} = principal_filter!(principal_type, principal_id)
    opts = page_options!(opts, [])
    visibility = company_visibility(scope, company_ids(scope, registry))

    query =
      from(assignment in PrincipalRole,
        join: role in Role,
        on: role.id == assignment.role_id,
        where: assignment.principal_type == ^principal_type,
        where: assignment.principal_id == ^principal_id,
        where: ^visibility
      )

    ordered_query =
      query
      |> order_by([assignment, role], asc: role.code, asc: assignment.id)
      |> select([assignment, role], %{assignment: assignment, role: role})

    page_query(
      query,
      ordered_query,
      opts,
      fn rows ->
        Enum.map(rows, fn %{assignment: assignment, role: role} ->
          PrincipalRoleSummary.from_schema(assignment, role)
        end)
      end
    )
  end

  defp page_query(count_query, ordered_query, opts, mapper) do
    page = page!(opts[:page])
    page_size = page_size!(opts[:page_size])
    total_entries = Repo.aggregate(count_query, :count, :id)

    entries =
      ordered_query
      |> offset(^((page - 1) * page_size))
      |> limit(^page_size)
      |> Repo.all()
      |> mapper.()

    %Page{
      entries: entries,
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages(total_entries, page_size)
    }
  end

  defp page_options!(opts, extra_defaults) do
    Keyword.validate!(opts, [page: 1, page_size: @default_page_size] ++ extra_defaults)
  end

  defp scoped_roles(company_ids) do
    from(role in Role,
      where:
        (role.is_system and is_nil(role.company_id)) or
          (not role.is_system and role.company_id in ^company_ids)
    )
  end

  defp role_summaries(roles, visibility) do
    ids = Enum.map(roles, & &1.id)
    capability_counts = counts_by(RoleCapability, :role_id, ids)
    principal_counts = principal_counts_by_role(ids, visibility)

    Enum.map(roles, fn role ->
      RoleSummary.from_schema(
        role,
        Map.get(capability_counts, role.id, 0),
        Map.get(principal_counts, role.id, 0)
      )
    end)
  end

  defp counts_by(_schema, _field, []), do: %{}

  defp counts_by(schema, field, ids) do
    schema
    |> where([row], field(row, ^field) in ^ids)
    |> group_by([row], field(row, ^field))
    |> select([row], {field(row, ^field), count(row.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp principal_counts_by_role([], _visibility), do: %{}

  defp principal_counts_by_role(role_ids, visibility) do
    PrincipalRole
    |> where([assignment], assignment.role_id in ^role_ids)
    |> where(^visibility)
    |> group_by([assignment], assignment.role_id)
    |> select([assignment], {assignment.role_id, count(assignment.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_search_roles(query, nil), do: query

  defp maybe_search_roles(query, search) do
    pattern = "%#{search}%"

    from(role in query,
      where:
        ilike(role.name, ^pattern) or ilike(role.code, ^pattern) or
          ilike(role.description, ^pattern)
    )
  end

  defp maybe_search_decision_logs(query, nil), do: query

  defp maybe_search_decision_logs(query, search) do
    pattern = "%#{search}%"

    from(log in query,
      where:
        ilike(log.capability, ^pattern) or ilike(log.reason_code, ^pattern) or
          ilike(log.resource_type, ^pattern) or ilike(log.resource_id, ^pattern) or
          ilike(log.actor_type, ^pattern) or ilike(log.trace_id, ^pattern)
    )
  end

  defp maybe_search_principal_roles(query, nil), do: query

  defp maybe_search_principal_roles(query, search) do
    pattern = "%#{search}%"

    from([assignment, role] in query,
      where:
        ilike(role.name, ^pattern) or ilike(role.code, ^pattern) or
          ilike(assignment.principal_type, ^pattern) or
          fragment("CAST(? AS TEXT) ILIKE ?", assignment.principal_id, ^pattern)
    )
  end

  defp order_principal_roles(query, :company_name, opts) do
    direction = sort_dir!(opts[:sort_dir])
    ids = company_order!(opts[:company_order])

    order_by(query, [assignment, _role], [
      {^direction, fragment("array_position(?::bigint[], ?)", ^ids, assignment.company_id)},
      {^direction, assignment.id}
    ])
  end

  defp order_principal_roles(query, :role_name, opts) do
    direction = sort_dir!(opts[:sort_dir])

    order_by(query, [assignment, role], [
      {^direction, role.name},
      {^direction, assignment.id}
    ])
  end

  defp order_principal_roles(query, sort_by, opts) do
    direction = sort_dir!(opts[:sort_dir])
    field = Map.fetch!(@principal_role_sort_fields, sort_by)

    order_by(query, [assignment, _role], [
      {^direction, field(assignment, ^field)},
      {^direction, assignment.id}
    ])
  end

  defp maybe_search_principal_capabilities(query, nil), do: query

  defp maybe_search_principal_capabilities(query, search) do
    pattern = "%#{search}%"

    from(grant in query,
      where:
        ilike(grant.capability_key, ^pattern) or
          ilike(grant.principal_type, ^pattern)
    )
  end

  defp maybe_filter_allowed(query, nil), do: query

  defp maybe_filter_allowed(query, allowed),
    do: from(log in query, where: log.allowed == ^allowed)

  defp maybe_filter_principal_allowed(query, nil), do: query

  defp maybe_filter_principal_allowed(query, allowed) do
    from(grant in query, where: grant.is_allowed == ^allowed)
  end

  defp filter_principal(query, nil), do: query

  defp filter_principal(query, {principal_type, principal_id}) do
    from(grant in query,
      where: grant.principal_type == ^principal_type and grant.principal_id == ^principal_id
    )
  end

  defp order_query(query, :company_name, opts, _fields) do
    direction = sort_dir!(opts[:sort_dir])
    ids = company_order!(opts[:company_order])

    order_by(query, [grant], [
      {^direction, fragment("array_position(?::bigint[], ?)", ^ids, grant.company_id)},
      {^direction, grant.id}
    ])
  end

  defp order_query(query, sort_by, opts, fields) do
    direction = sort_dir!(opts[:sort_dir])
    field = Map.fetch!(fields, sort_by)
    order_by(query, ^[{direction, field}, {direction, :id}])
  end

  defp company_order!(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and length(ids) == length(Enum.uniq(ids)) do
      ids
    else
      raise ArgumentError,
            "company_order must be unique positive integer IDs, got: #{inspect(ids)}"
    end
  end

  defp company_order!(value) do
    raise ArgumentError,
          "company_order must be a list of unique positive integer IDs, got: #{inspect(value)}"
  end

  defp search!(nil), do: nil

  defp search!(search) when is_binary(search) do
    case String.trim(search) do
      "" -> nil
      value -> value
    end
  end

  defp search!(value),
    do: raise(ArgumentError, "search must be a string or nil, got: #{inspect(value)}")

  defp allowed!(value) when is_nil(value) or is_boolean(value), do: value

  defp allowed!(value) do
    raise ArgumentError, "allowed filter must be true, false, or nil, got: #{inspect(value)}"
  end

  defp principal_filter!(nil, nil), do: nil

  defp principal_filter!(principal_type, principal_id)
       when principal_type in [:user, :agent] and is_integer(principal_id) and principal_id > 0 do
    {Atom.to_string(principal_type), principal_id}
  end

  defp principal_filter!(principal_type, principal_id) do
    raise ArgumentError,
          "principal filter must be a :user or :agent with a positive ID, got: " <>
            inspect({principal_type, principal_id})
  end

  defp sort_by!(value, fields) do
    if Map.has_key?(fields, value) do
      value
    else
      raise ArgumentError,
            "sort_by must be one of #{inspect(Map.keys(fields))}, got: #{inspect(value)}"
    end
  end

  defp sort_dir!(value) when value in [:asc, :desc], do: value

  defp sort_dir!(value),
    do: raise(ArgumentError, "sort_dir must be :asc or :desc, got: #{inspect(value)}")

  defp page!(value) when is_integer(value) and value > 0, do: value

  defp page!(value),
    do: raise(ArgumentError, "page must be a positive integer, got: #{inspect(value)}")

  defp page_size!(value) when is_integer(value) and value in 1..@maximum_page_size, do: value

  defp page_size!(value) do
    raise ArgumentError,
          "page_size must be between 1 and #{@maximum_page_size}, got: #{inspect(value)}"
  end

  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_entries, page_size), do: div(total_entries + page_size - 1, page_size)

  defp company_ids(%Scope{} = scope, registry), do: directory!(registry).company_ids(scope)

  defp company_visibility(%Scope{} = scope, company_ids) do
    if Scope.platform_operator?(scope) do
      dynamic([row], row.company_id in ^company_ids or is_nil(row.company_id))
    else
      dynamic([row], row.company_id in ^company_ids)
    end
  end

  defp humanize_module(owner) when is_binary(owner) do
    owner
    |> String.split("/")
    |> Enum.map_join(" / ", &Macro.camelize/1)
  end

  defp humanize_module(_), do: "Unknown"

  defp domain_filter!(nil), do: nil

  defp domain_filter!(domain) when is_binary(domain) do
    case String.trim(domain) do
      "" -> nil
      value -> value
    end
  end

  defp domain_filter!(value),
    do: raise(ArgumentError, "domain must be a string or nil, got: #{inspect(value)}")

  defp maybe_search_capabilities(items, nil), do: items

  defp maybe_search_capabilities(items, search) do
    search = String.downcase(search)

    Enum.filter(items, fn %CapabilitySummary{key: key, module: module} ->
      String.contains?(String.downcase(key), search) or
        String.contains?(String.downcase(module), search)
    end)
  end

  defp maybe_filter_capability_domain(items, nil), do: items

  defp maybe_filter_capability_domain(items, domain) do
    Enum.filter(items, fn %CapabilitySummary{domain: d} -> d == domain end)
  end

  defp sort_capabilities(items, sort_by, sort_dir) do
    dir = if sort_dir == :desc, do: -1, else: 1

    Enum.sort(items, fn a, b ->
      left = Map.fetch!(a, sort_by)
      right = Map.fetch!(b, sort_by)

      cmp = compare_values(left, right)

      if cmp != 0 do
        dir * cmp <= 0
      else
        compare_values(a.key, b.key) <= 0
      end
    end)
  end

  defp compare_values(left, right) when is_binary(left) and is_binary(right) do
    l = String.downcase(left)
    r = String.downcase(right)

    cond do
      l < r -> -1
      l > r -> 1
      true -> 0
    end
  end

  defp compare_values(left, right) do
    cond do
      left < right -> -1
      left > right -> 1
      true -> 0
    end
  end

  defp directory!(%{company_directory: nil}) do
    raise ArgumentError, "no installed module contributes the Authz company directory"
  end

  defp directory!(%{company_directory: directory}), do: directory
end
