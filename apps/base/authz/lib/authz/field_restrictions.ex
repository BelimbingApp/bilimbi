defmodule Bilimbi.Base.Authz.FieldRestrictions do
  @moduledoc """
  Field restrictions an operator sets at runtime, per tenant.

  Every field is visible by default. A restriction names one field of one
  catalog table, in the vocabulary `Bilimbi.Base.Grid` installs
  (`companies` / `email`), and the roles it is restricted for. A reader who
  holds any of those roles reads the field as `Bilimbi.Base.Authz.Restricted`:
  on the record page, in grid columns, in the audit views, and on create and
  update, where any submitted value is refused whatever it is. Everyone else
  sees the value.

  The catalog of what may be restricted is read from the installed `:grid`
  contribution snapshot as plain data, so Base Authz keeps no dependency on
  Base Grid. A field is restrictable unless its owner protected it (`protected:
  true`), it is hidden, it is the table's key, label or time field, or a link
  joins on it: those are what every reader of the table needs.

  The decision for a reader is made from the roles assigned to the scope's
  actor in the company they signed in at, read afresh on every ask, so a role
  revoked or a restriction removed takes effect on the next check, on any
  node and inside an open LiveView. The restriction wins: a reader holding a
  restricted role and an unrestricted one is restricted. A grant-all role
  earns no exemption; listing it restricts its holders like any other. A
  named system principal and an anonymous system scope hold no roles, so
  nothing is restricted for them: a field is visible unless a role the
  reader holds is named.
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
  Restricts `field_id` of `table_id` for `role_ids` in the scope's tenant,
  creating the restriction or replacing the roles of the existing one.

  The field must be restrictable (`catalog/0`), at least one role must be
  named (`:no_roles`: a restriction for nobody restricts nothing), and every
  role must be one the scope may see: a system role, or a custom role of a
  live company in the tenant. The write and a retained
  `authz.field_restriction.set` audit action naming the operator commit
  together.
  """
  @spec put(Scope.t(), String.t(), String.t(), [pos_integer()], operator(), map()) ::
          {:ok, FieldRestrictionSummary.t()}
          | {:error,
             :not_restrictable
             | :no_roles
             | {:unknown_roles, [pos_integer()]}
             | :audit_unavailable}
  def put(%Scope{} = scope, table_id, field_id, role_ids, operator, registry)
      when is_binary(table_id) and is_binary(field_id) and is_list(role_ids) do
    role_ids = role_ids |> Enum.uniq() |> Enum.sort()

    with :ok <- restrictable(table_id, field_id),
         :ok <- some_roles(role_ids),
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

        record!(scope, "authz.field_restriction.set", restriction, role_ids, operator, registry)

        scope
        |> list(registry)
        |> Enum.find(&(&1.id == restriction.id))
      end)
    end
  end

  @doc """
  Restricts several catalog fields for the same `role_ids` at once, as one
  transaction: either every field is restricted or none is.

  `fields` are `{table_id, field_id}` pairs; duplicates are ignored and an
  empty list is `:no_fields`, as an empty role list is `:no_roles`. Every
  field must be restrictable and every role in scope, checked before
  anything is written, so a mistaken pick does not leave half the batch
  behind. Each field keeps its own restriction row and
  its own retained `authz.field_restriction.set` audit action, exactly as if
  restricted alone (`put/6`): the batch is the operator's convenience, not a
  new kind of record.
  """
  @spec put_many(Scope.t(), [{String.t(), String.t()}], [pos_integer()], operator(), map()) ::
          {:ok, [FieldRestrictionSummary.t()]}
          | {:error,
             :no_fields
             | :no_roles
             | :not_restrictable
             | {:unknown_roles, [pos_integer()]}
             | :audit_unavailable}
  def put_many(%Scope{} = scope, fields, role_ids, operator, registry)
      when is_list(fields) and is_list(role_ids) do
    fields = Enum.uniq(fields)
    role_ids = role_ids |> Enum.uniq() |> Enum.sort()

    with :ok <- some_fields(fields),
         :ok <- all_restrictable(fields),
         :ok <- some_roles(role_ids),
         :ok <- roles_in_scope(scope, role_ids, registry) do
      transaction(fn ->
        Enum.map(fields, fn {table_id, field_id} ->
          case put(scope, table_id, field_id, role_ids, operator, registry) do
            {:ok, restriction} -> restriction
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
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
  The fields the scope's actor may not see: `%{table_id => [field_id]}`, each
  list sorted.

  A field is withheld when the actor holds any of the roles its restriction
  names; the restriction wins over every other role they hold. One query for
  the tenant's restrictions; when there are any, one more for the roles the
  actor holds in the company they signed in at. A table with nothing
  restricted for this actor is absent, and a system scope, holding no role,
  is restricted nowhere.
  """
  @spec restricted(Scope.t(), map() | (-> map())) ::
          %{String.t() => [String.t()]}
  def restricted(%Scope{} = scope, registry) do
    case restrictions_with_roles(scope) do
      [] ->
        %{}

      restrictions ->
        # The registry is read only now: a tenant with no restriction, the
        # common case, costs one query and needs no contribution snapshot.
        held = held_role_ids(scope, resolve(registry))

        restrictions
        |> Enum.filter(fn r -> Enum.any?(r.roles, &MapSet.member?(held, &1.role_id)) end)
        |> Enum.group_by(& &1.table_id, & &1.field_id)
        |> Map.new(fn {table_id, field_ids} -> {table_id, Enum.sort(field_ids)} end)
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
    case Map.get(restricted(scope, registry), table_id, []) do
      [] ->
        records

      field_ids ->
        markers =
          Map.new(field_ids, fn field_id ->
            {field_id, %Restricted{table_id: table_id, field_id: field_id}}
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
  # scope, named or not, holds none, so nothing is restricted for it.
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

  defp restrictable(table_id, field_id) do
    if restrictable?(table_id, field_id), do: :ok, else: {:error, :not_restrictable}
  end

  defp some_fields([]), do: {:error, :no_fields}
  defp some_fields(_fields), do: :ok

  defp some_roles([]), do: {:error, :no_roles}
  defp some_roles(_role_ids), do: :ok

  defp all_restrictable(fields) do
    catalog = catalog()

    restrictable? = fn
      {table_id, field_id} when is_binary(table_id) and is_binary(field_id) ->
        Enum.any?(catalog, fn table ->
          table.id == table_id and Enum.any?(table.fields, &(&1.id == field_id))
        end)

      _other ->
        false
    end

    if Enum.all?(fields, restrictable?), do: :ok, else: {:error, :not_restrictable}
  end

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
      case event do
        "authz.field_restriction.removed" -> "#{verb} #{subject}"
        _set -> "#{verb} #{subject} for #{Enum.join(roles, ", ")}"
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
