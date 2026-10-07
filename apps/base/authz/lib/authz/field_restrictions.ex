defmodule Bilimbi.Base.Authz.FieldRestrictions do
  @moduledoc """
  Field access restrictions an operator sets at runtime, per tenant.

  A restriction names one field of one catalog table, in the vocabulary
  `Bilimbi.Base.Grid` installs (`companies` / `email`), and the roles that
  still see it. Everyone else in the tenant reads the field as
  `Bilimbi.Base.Authz.Restricted`: on the record page, in grid columns, in
  the audit views, and on create and update, where any submitted value is
  refused whatever it is.

  The catalog of what may be restricted is read from the installed `:grid`
  contribution snapshot as plain data, so Base Authz keeps no dependency on
  Base Grid. A field is restrictable unless its owner protected it (`protected:
  true`), it is hidden, it is the table's key, label or time field, or a link
  joins on it: those are what every reader of the table needs.

  The decision for a reader is made from the roles assigned to the scope's
  actor in the company they signed in at, read afresh on every ask, so a role
  revoked or a restriction removed takes effect on the next check, on any
  node and inside an open LiveView. A named system principal and an
  anonymous system scope hold no roles, so every restricted field is
  withheld from them.
  """

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.EffectivePermissions
  alias Bilimbi.Base.Authz.FieldRestriction
  alias Bilimbi.Base.Authz.FieldRestrictionRole
  alias Bilimbi.Base.Authz.FieldRestrictionSummary
  alias Bilimbi.Base.Authz.Restricted
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleService
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope

  @typedoc "Who performed the change, as `Bilimbi.Base.Authz` names the signed-in user."
  @type operator :: %{
          required(:actor_type) => String.t(),
          required(:actor_id) => non_neg_integer(),
          optional(:company_id) => pos_integer() | nil,
          optional(:impersonator_id) => pos_integer() | nil
        }

  @typedoc "One restrictable field of the catalog."
  @type catalog_field :: %{id: String.t(), label: String.t()}

  @typedoc "One table of the catalog with the fields an operator may restrict."
  @type catalog_table :: %{
          id: String.t(),
          label: String.t(),
          record_types: [String.t()],
          fields: [catalog_field()]
        }

  @doc """
  The tables and fields an operator may restrict, in catalog order.

  A table with no restrictable field is left out.
  """
  @spec catalog() :: [catalog_table()]
  def catalog do
    tables = installed_tables()
    joined = join_fields(tables)

    tables
    |> Map.values()
    |> Enum.sort_by(& &1.label)
    |> Enum.map(fn table ->
      fields =
        table.field_order
        |> Enum.map(&Map.fetch!(table.fields, &1))
        |> Enum.reject(&protected_field?(table, &1, joined))
        |> Enum.map(&%{id: &1.id, label: &1.label})

      %{id: table.id, label: table.label, record_types: table.record_types, fields: fields}
    end)
    |> Enum.reject(&(&1.fields == []))
  end

  @doc "Whether `field_id` of `table_id` is in the restrictable catalog."
  @spec restrictable?(String.t(), String.t()) :: boolean()
  def restrictable?(table_id, field_id) when is_binary(table_id) and is_binary(field_id) do
    Enum.any?(catalog(), fn table ->
      table.id == table_id and Enum.any?(table.fields, &(&1.id == field_id))
    end)
  end

  @doc "The tenant's restrictions, ordered by table and field, with their roles named."
  @spec list(Scope.t(), map()) :: [FieldRestrictionSummary.t()]
  def list(%Scope{} = scope, registry) do
    tables = installed_tables()
    role_names = scope |> RoleService.list_roles(registry) |> Map.new(&{&1.id, &1.name})

    scope
    |> restrictions_with_roles()
    |> Enum.map(fn restriction ->
      table = Map.get(tables, restriction.table_id)
      field = table && Map.get(table.fields, restriction.field_id)
      role_ids = restriction.roles |> Enum.map(& &1.role_id) |> Enum.sort()

      %FieldRestrictionSummary{
        id: restriction.id,
        table_id: restriction.table_id,
        table_label: (table && table.label) || restriction.table_id,
        field_id: restriction.field_id,
        field_label: (field && field.label) || restriction.field_id,
        created_at: restriction.created_at,
        updated_at: restriction.updated_at,
        role_ids: role_ids,
        role_names:
          role_ids |> Enum.map(&Map.get(role_names, &1)) |> Enum.reject(&is_nil/1) |> Enum.sort()
      }
    end)
    |> Enum.sort_by(&{&1.table_label, &1.field_label, &1.id})
  end

  @doc """
  Restricts `field_id` of `table_id` to `role_ids` in the scope's tenant,
  creating the restriction or replacing the roles of the existing one.

  The field must be restrictable (`catalog/0`), and every role must be one
  the scope may see: a system role, or a custom role of a live company in the
  tenant. The write and a retained `authz.field_restriction.set` audit action
  naming the operator commit together.
  """
  @spec put(Scope.t(), String.t(), String.t(), [pos_integer()], operator(), map()) ::
          {:ok, FieldRestrictionSummary.t()}
          | {:error, :not_restrictable | {:unknown_roles, [pos_integer()]} | :audit_unavailable}
  def put(%Scope{} = scope, table_id, field_id, role_ids, operator, registry)
      when is_binary(table_id) and is_binary(field_id) and is_list(role_ids) do
    role_ids = role_ids |> Enum.uniq() |> Enum.sort()

    with :ok <- restrictable(table_id, field_id),
         :ok <- roles_in_scope(scope, role_ids, registry) do
      tenant_id = Scope.tenant_id(scope)

      transaction(fn ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        {1, [restriction]} =
          Repo.insert_all(
            FieldRestriction,
            [
              %{
                tenant_id: tenant_id,
                table_id: table_id,
                field_id: field_id,
                created_at: now,
                updated_at: now
              }
            ],
            on_conflict: {:replace, [:updated_at]},
            conflict_target: [:tenant_id, :table_id, :field_id],
            returning: [:id, :table_id, :field_id]
          )

        Repo.delete_all(
          from(rr in FieldRestrictionRole, where: rr.restriction_id == ^restriction.id)
        )

        if role_ids != [] do
          Repo.insert_all(
            FieldRestrictionRole,
            Enum.map(role_ids, fn role_id ->
              %{
                restriction_id: restriction.id,
                role_id: role_id,
                created_at: now,
                updated_at: now
              }
            end)
          )
        end

        record!(scope, "authz.field_restriction.set", restriction, role_ids, operator, registry)

        scope
        |> list(registry)
        |> Enum.find(&(&1.id == restriction.id))
      end)
    end
  end

  @doc """
  Removes one restriction of the scope's tenant by its durable id. A
  retained `authz.field_restriction.removed` action naming the operator
  commits with it. A restriction that does not exist, or belongs to another
  tenant, is `{:ok, :not_found}`.
  """
  @spec remove(Scope.t(), pos_integer(), operator(), map()) ::
          {:ok, :removed | :not_found} | {:error, :audit_unavailable}
  def remove(%Scope{} = scope, restriction_id, operator, registry)
      when is_integer(restriction_id) and restriction_id > 0 do
    case Repo.one(
           from(r in Tenancy.scope_query(FieldRestriction, scope),
             where: r.id == ^restriction_id,
             preload: :roles
           )
         ) do
      nil ->
        {:ok, :not_found}

      restriction ->
        transaction(fn ->
          role_ids = Enum.map(restriction.roles, & &1.role_id)
          Repo.delete!(restriction)

          record!(
            scope,
            "authz.field_restriction.removed",
            restriction,
            role_ids,
            operator,
            registry
          )

          :removed
        end)
    end
  end

  def remove(%Scope{}, _restriction_id, _operator, _registry), do: {:ok, :not_found}

  @doc """
  The fields the scope's actor may not see, as `%{table_id => [field_id]}`,
  with the roles that see each: `%{table_id => %{field_id => [role_name]}}`.

  One query for the tenant's restrictions; when there are any, one more for
  the roles the actor holds in the company they signed in at. A table with
  nothing restricted for this actor is absent.
  """
  @spec restricted(Scope.t(), map() | (-> map())) ::
          %{String.t() => %{String.t() => [String.t()]}}
  def restricted(%Scope{} = scope, registry) do
    case restrictions_with_roles(scope) do
      [] ->
        %{}

      restrictions ->
        # The registry is read only now: a tenant with no restriction, the
        # common case, costs one query and needs no contribution snapshot.
        held = held_role_ids(scope, resolve(registry))

        names =
          restrictions
          |> Enum.flat_map(fn r -> Enum.map(r.roles, & &1.role_id) end)
          |> role_names()

        restrictions
        |> Enum.reject(fn r -> Enum.any?(r.roles, &MapSet.member?(held, &1.role_id)) end)
        |> Enum.group_by(& &1.table_id)
        |> Map.new(fn {table_id, rows} ->
          {table_id,
           Map.new(rows, fn r ->
             {r.field_id,
              r.roles |> Enum.map(&Map.get(names, &1.role_id)) |> Enum.reject(&is_nil/1)}
           end)}
        end)
    end
  end

  @doc """
  Replaces the restricted fields of `table_id` in `record` (or each of a
  list) with a `Restricted` marker. A field id that names no key of the
  record is skipped: a catalog field a read model does not carry has nothing
  to withhold.
  """
  @spec redact(Scope.t(), String.t(), record, map() | (-> map())) :: record
        when record: struct() | [struct()]
  def redact(%Scope{} = scope, table_id, records, registry) when is_binary(table_id) do
    case Map.get(restricted(scope, registry), table_id, %{}) do
      fields when fields == %{} ->
        records

      fields ->
        markers =
          Map.new(fields, fn {field_id, roles} ->
            {field_id, %Restricted{table_id: table_id, field_id: field_id, roles: roles}}
          end)

        case records do
          list when is_list(list) -> Enum.map(list, &withhold(&1, markers))
          %_{} = record -> withhold(record, markers)
        end
    end
  end

  @doc """
  Refuses a write that names a restricted field, whatever value it carries.

  `attrs` are the submitted attributes with string or atom keys. Every
  restricted field named in them, changed or not, gets an error on the
  changeset, so the refusal never depends on what is stored and cannot
  confirm a guess.
  """
  @spec refuse_attempts(Ecto.Changeset.t(), [String.t()], map()) :: Ecto.Changeset.t()
  def refuse_attempts(%Ecto.Changeset{} = changeset, restricted_fields, attrs)
      when is_list(restricted_fields) and is_map(attrs) do
    submitted = attrs |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()

    Enum.reduce(restricted_fields, changeset, fn field_id, acc ->
      if MapSet.member?(submitted, field_id) do
        field = Enum.find(Map.keys(acc.data), &(Atom.to_string(&1) == field_id))

        if field,
          do: Ecto.Changeset.add_error(acc, field, "is restricted and cannot be changed"),
          else: acc
      else
        acc
      end
    end)
  end

  # --- private ---------------------------------------------------------------

  defp resolve(registry) when is_function(registry, 0), do: registry.()
  defp resolve(registry) when is_map(registry), do: registry

  defp withhold(%_{} = record, markers) do
    Enum.reduce(markers, record, fn {field_id, marker}, acc ->
      case Enum.find(Map.keys(acc), &(Atom.to_string(&1) == field_id)) do
        nil -> acc
        key -> Map.put(acc, key, marker)
      end
    end)
  end

  defp restrictions_with_roles(scope) do
    from(r in Tenancy.scope_query(FieldRestriction, scope),
      order_by: [asc: r.table_id, asc: r.field_id, asc: r.id],
      preload: :roles
    )
    |> Repo.all()
  end

  # The roles the actor holds in the company they signed in at. A system
  # scope, named or not, holds none.
  defp held_role_ids(%Scope{} = scope, registry) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id, company_id: company_id} ->
        actor = Actor.new!(:user, user_id, scope, company_id)

        case EffectivePermissions.live_company_roles(actor, directory!(registry)) do
          {:ok, _company_id, {role_ids, _grant_all}} -> MapSet.new(role_ids)
          :out_of_scope -> MapSet.new()
        end

      %TenancyActor{type: :system} ->
        MapSet.new()
    end
  end

  defp role_names([]), do: %{}

  defp role_names(role_ids) do
    from(role in Role, where: role.id in ^Enum.uniq(role_ids), select: {role.id, role.name})
    |> Repo.all()
    |> Map.new()
  end

  defp restrictable(table_id, field_id) do
    if restrictable?(table_id, field_id), do: :ok, else: {:error, :not_restrictable}
  end

  defp roles_in_scope(_scope, [], _registry), do: :ok

  defp roles_in_scope(scope, role_ids, registry) do
    malformed = Enum.reject(role_ids, &(is_integer(&1) and &1 > 0))

    if malformed != [] do
      {:error, {:unknown_roles, malformed}}
    else
      visible = scope |> RoleService.role_grants(role_ids, registry) |> Map.keys()

      case role_ids -- visible do
        [] -> :ok
        unknown -> {:error, {:unknown_roles, unknown}}
      end
    end
  end

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record!(scope, event, restriction, role_ids, operator, registry) do
    context = AuditContext.get()
    verb = if event == "authz.field_restriction.set", do: "Restricted", else: "Unrestricted"
    names = scope |> RoleService.list_roles(registry) |> Map.new(&{&1.id, &1.name})
    roles = role_ids |> Enum.map(&Map.get(names, &1, "role ##{&1}")) |> Enum.sort()
    subject = "#{restriction.table_id}.#{restriction.field_id}"

    summary =
      case {event, roles} do
        {"authz.field_restriction.removed", _} -> "#{verb} #{subject}"
        {_, []} -> "#{verb} #{subject} to no role"
        {_, roles} -> "#{verb} #{subject} to #{Enum.join(roles, ", ")}"
      end

    attributes = %{
      company_id: Map.get(operator, :company_id),
      actor_type: operator.actor_type,
      actor_id: operator.actor_id,
      impersonator_id: Map.get(operator, :impersonator_id),
      system_principal: nil,
      ip_address: context.ip_address,
      url: context.url,
      user_agent: context.user_agent && String.slice(context.user_agent, 0, 80),
      trace_id: context.trace_id && String.slice(context.trace_id, 0, 12),
      event: event,
      payload: %{
        "semantic" => true,
        "source" => "Authz",
        "summary" => summary,
        "subject" => %{"name" => "field_restriction", "id" => restriction.id, "label" => subject},
        "context" => %{
          "table_id" => restriction.table_id,
          "field_id" => restriction.field_id,
          "role_ids" => role_ids,
          "roles" => roles
        },
        "result" => "succeeded"
      },
      is_retained: true,
      occurred_at: NaiveDateTime.utc_now()
    }

    case Audit.record_action(scope, attributes) do
      {:ok, _action} -> :ok
      {:error, _changeset} -> Repo.rollback(:audit_unavailable)
    end
  end

  # The installed grid catalog as plain maps: Base Authz reads the snapshot's
  # data and keeps no dependency on Base Grid.
  defp installed_tables do
    case ContributionRegistry.consumer!(:grid) do
      %{tables: tables} when is_map(tables) -> tables
      _none -> %{}
    end
  end

  defp join_fields(tables) do
    tables
    |> Map.values()
    |> Enum.flat_map(fn table ->
      table
      |> Map.get(:links, %{})
      |> Map.values()
      |> Enum.flat_map(fn
        %{on: {from_field, to_field}, to: to} -> [{table.id, from_field}, {to, to_field}]
        _edge -> []
      end)
    end)
    |> MapSet.new()
  end

  defp protected_field?(table, field, joined) do
    Map.get(field, :hidden, false) or Map.get(field, :protected, false) or
      field.id in [table.key, Map.get(table, :label_field), Map.get(table, :time_field)] or
      MapSet.member?(joined, {table.id, field.id})
  end

  defp directory!(%{company_directory: nil}) do
    raise ArgumentError, "no installed module contributes the Authz company directory"
  end

  defp directory!(%{company_directory: directory}), do: directory
end
