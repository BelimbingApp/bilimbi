defmodule Bilimbi.Base.Audit.MutationCapture do
  @moduledoc """
  Shapes captured repo writes into canonical `base_audit_mutations` rows
  (ADR 0013, #630) — the port of Belimbing's wildcard `MutationListener`.

  Base Database's `WriteCapture` seam calls `after_write/3` after every
  successful struct write and `after_bulk_write/2` after every successful
  query-based bulk write; this module owns the policy for both, from one
  set of functions:

    * actor columns come from the per-process `Audit.Context`, guest/0 when
      absent — the source's `PrincipalType::GUEST` default — and so does
      `impersonator_id`, the operator behind an impersonated session;
    * `tenant_id` prefers the mutated row's own `tenant_id` attribute over
      the context — the row is ground truth, as in the source;
    * updates record changed fields only, with their originals; creates
      record the new attributes; deletes record the old ones — empty diffs
      write nothing;
    * globally redacted fields (`password`, `password_hash`,
      `remember_token`, `secret`, `api_key`, `token`, `payload`) appear as
      `[redacted]`; the change is recorded, the value never is. `payload`
      is the durable session's opaque Laravel blob, which can carry a CSRF
      token or a password hash that no field name reveals. Long
      strings are bounded by `Bilimbi.Base.Audit.PayloadText`;
    * `auditable_type` defaults to the Ecto schema module name; a schema
      that must match a Belimbing morph string defines
      `__audit_auditable_type__/0`;
    * Base Audit's own schemas are never captured, and further exclusions
      live in `:bilimbi_base_audit, :exclude_schemas` — the port of
      `audit.exclude_models`, one justified entry at a time.

  Rows are inserted synchronously in the caller's process, inside any open
  transaction: a rolled-back write rolls its audit row back with it. The
  seam guarantees a capture failure never fails the business write.

  A bulk write produces one `insert_all` of audit rows per 1,000 affected
  rows, never one insert per affected row: the per-row cost of capture is an
  Elixir round trip, not database work, and a row-at-a-time capture measured
  about 33x worse on a large batch (#785). The chunk keeps each statement
  far below PostgreSQL's 65,535 bind-parameter ceiling.
  """

  @behaviour Bilimbi.Base.Database.WriteCapture

  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.PayloadText
  alias Bilimbi.Base.Repo

  # Redact here, in the shared policy. A call site does not invent its own
  # masking. `payload` is the opaque session blob, which can carry a secret
  # no field name reveals.
  @redacted_fields ~w(password password_hash remember_token secret api_key token payload)a
  @redacted_marker "[redacted]"
  @bulk_chunk_size 1000
  @excluded_schemas [ActionSchema, MutationSchema]

  @impl true
  def capture_schema?(schema) when is_atom(schema), do: captured_schema?(schema)

  @impl true
  def after_write(action, source, %schema{} = result) do
    if captured_schema?(schema) do
      case values(action, source, result) do
        nil ->
          :ok

        {old_values, new_values} ->
          context = Context.get()

          %{
            company_id: context.company_id,
            actor_type: context.actor_type,
            actor_id: context.actor_id,
            actor_role: context.actor_role,
            impersonator_id: context.impersonator_id,
            ip_address: context.ip_address,
            url: context.url,
            user_agent: bounded(context.user_agent, 80),
            auditable_type: auditable_type(schema),
            auditable_id: auditable_id(result),
            source: "listener",
            event: event(action),
            old_values: old_values,
            new_values: new_values,
            trace_id: bounded(context.trace_id, 12),
            occurred_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
          }
          |> MutationSchema.changeset(tenant_id(result, context))
          |> insert_capture()
      end
    else
      :ok
    end
  end

  def after_write(_action, _source, _result), do: :ok

  @impl true
  def after_bulk_write(schema, changes) do
    if captured_schema?(schema) do
      context = Context.get()

      changes
      |> Enum.map(&mutation_attributes(schema, &1, context))
      |> Enum.reject(&is_nil/1)
      |> insert_bulk_capture()
    else
      :ok
    end
  end

  # The same canonical row as a struct write, reached through the same
  # changeset: `insert_all` dumps but does not cast, so the changeset is
  # applied first and its cast values — `ip_address` among them — become
  # the batched entry.
  defp mutation_attributes(schema, {action, old_row, new_row}, context) do
    row = new_row || old_row

    case bulk_values(action, old_row, new_row) do
      nil ->
        nil

      {old_values, new_values} ->
        %{
          company_id: context.company_id,
          actor_type: context.actor_type,
          actor_id: context.actor_id,
          actor_role: context.actor_role,
          impersonator_id: context.impersonator_id,
          ip_address: context.ip_address,
          url: context.url,
          user_agent: bounded(context.user_agent, 80),
          auditable_type: auditable_type(schema),
          auditable_id: auditable_id(row),
          source: "listener",
          event: event(action),
          old_values: old_values,
          new_values: new_values,
          trace_id: bounded(context.trace_id, 12),
          occurred_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
        }
        |> MutationSchema.changeset(tenant_id(row, context))
        |> batched_entry()
    end
  end

  defp bulk_values(:insert, _old_row, new_row), do: nonempty({%{}, sanitized_attributes(new_row)})
  defp bulk_values(:delete, old_row, _new_row), do: nonempty({sanitized_attributes(old_row), %{}})

  # A concurrent write can leave an updated row with no known original; it
  # records the full new row rather than a diff against a guess, the same
  # answer the struct path gives a non-changeset update.
  defp bulk_values(:update, nil, new_row), do: nonempty({%{}, sanitized_attributes(new_row)})

  defp bulk_values(:update, old_row, %schema{} = new_row) do
    changed =
      schema.__schema__(:fields)
      |> Enum.filter(fn field ->
        storable_value?(Map.get(new_row, field)) and
          Map.get(old_row, field) != Map.get(new_row, field)
      end)

    if changed == [] do
      nil
    else
      {sanitize(Map.new(changed, &{&1, Map.get(old_row, &1)})),
       sanitize(Map.new(changed, &{&1, Map.get(new_row, &1)}))}
    end
  end

  defp batched_entry(changeset) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, mutation} -> mutation |> Map.from_struct() |> Map.drop([:__meta__, :id])
      {:error, invalid} -> raise Ecto.InvalidChangesetError, action: :insert, changeset: invalid
    end
  end

  defp insert_bulk_capture([]), do: :ok

  defp insert_bulk_capture(entries) do
    opts = if Repo.in_transaction?(), do: [mode: :savepoint], else: []

    entries
    |> Enum.chunk_every(@bulk_chunk_size)
    |> Enum.each(&Repo.insert_all(MutationSchema, &1, opts))

    :ok
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  # Inside a caller's transaction the row is written under a savepoint
  # (DBConnection's `mode: :savepoint`), so a failed capture rolls back to
  # its own savepoint instead of aborting the business transaction — the
  # business write's fate must never depend on the audit row's. A missing
  # audit table is the pre-canonical state (fixture suites, fresh checkouts
  # before migration) and is silently not captured; every other failure
  # propagates to the seam, which logs and counts it.
  defp insert_capture(changeset) do
    opts = if Repo.in_transaction?(), do: [mode: :savepoint], else: []
    Repo.insert!(changeset, opts)
    :ok
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp captured_schema?(schema) do
    excluded =
      @excluded_schemas ++ Application.get_env(:bilimbi_base_audit, :exclude_schemas, [])

    schema not in excluded
  end

  defp bounded(nil, _max), do: nil
  defp bounded(value, max) when is_binary(value), do: String.slice(value, 0, max)

  defp event(:insert), do: "created"
  defp event(:update), do: "updated"
  defp event(:delete), do: "deleted"

  defp auditable_type(schema) do
    if function_exported?(schema, :__audit_auditable_type__, 0) do
      schema.__audit_auditable_type__()
    else
      inspect(schema)
    end
  end

  defp auditable_id(%schema{} = result) do
    case schema.__schema__(:primary_key) do
      [key | _rest] -> result |> Map.get(key) |> to_string()
      [] -> nil
    end
  end

  # The mutated row's own tenant is ground truth; the request context is
  # the fallback — the source's resolveTenantId order.
  defp tenant_id(result, context) do
    case Map.get(result, :tenant_id) do
      tenant_id when is_integer(tenant_id) -> tenant_id
      _other -> context.tenant_id
    end
  end

  defp values(:insert, _source, result), do: nonempty({%{}, sanitized_attributes(result)})
  defp values(:delete, source, _result), do: nonempty({sanitized_attributes(source), %{}})

  defp values(:update, %Ecto.Changeset{} = changeset, _result) do
    changed =
      changeset.changes
      |> Enum.filter(fn {_field, value} -> storable_value?(value) end)
      |> Map.new()

    if map_size(changed) == 0 do
      nil
    else
      originals = Map.new(changed, fn {field, _v} -> {field, Map.get(changeset.data, field)} end)
      {sanitize(originals), sanitize(changed)}
    end
  end

  # A struct update (Repo.update requires a changeset, so this is only a
  # theoretical shape) records the full row rather than guessing a diff.
  defp values(:update, _source, result), do: nonempty({%{}, sanitized_attributes(result)})

  defp nonempty({_old, new_values} = pair) when map_size(new_values) > 0, do: pair
  defp nonempty({old_values, _new}) when map_size(old_values) > 0, do: {old_values, %{}}
  defp nonempty(_pair), do: nil

  defp sanitized_attributes(%Ecto.Changeset{data: data}), do: sanitized_attributes(data)

  defp sanitized_attributes(%schema{} = struct) do
    schema.__schema__(:fields)
    |> Map.new(fn field -> {field, Map.get(struct, field)} end)
    |> Enum.filter(fn {_field, value} -> storable_value?(value) end)
    |> Map.new()
    |> sanitize()
  end

  # Associations, embeds-not-loaded, and other non-serializable values stay
  # out of the JSON payload; scalar and map/list values are the record.
  defp storable_value?(%Ecto.Association.NotLoaded{}), do: false
  defp storable_value?(%Ecto.Changeset{}), do: false
  defp storable_value?(_value), do: true

  defp sanitize(values) do
    Map.new(values, fn {field, value} -> {field, field_value(field, value)} end)
  end

  defp field_value(field, _value) when field in @redacted_fields, do: @redacted_marker

  defp field_value(_field, value) when is_binary(value), do: PayloadText.bounded(value)

  defp field_value(_field, %NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp field_value(_field, %DateTime{} = value), do: DateTime.to_iso8601(value)
  defp field_value(_field, %Date{} = value), do: Date.to_iso8601(value)
  defp field_value(_field, %Time{} = value), do: Time.to_iso8601(value)
  defp field_value(_field, value), do: value
end
