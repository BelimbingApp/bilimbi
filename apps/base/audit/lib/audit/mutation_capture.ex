defmodule Bilimbi.Base.Audit.MutationCapture do
  @moduledoc """
  Shapes captured repo writes into canonical `base_audit_mutations` rows
  (ADR 0013, #630) — the port of Belimbing's wildcard `MutationListener`.

  Base Database's `WriteCapture` seam calls `after_write/3` after every
  successful struct write; this module owns the policy:

    * actor columns come from the per-process `Audit.Context`, guest/0 when
      absent — the source's `PrincipalType::GUEST` default;
    * `tenant_id` prefers the mutated row's own `tenant_id` attribute over
      the context — the row is ground truth, as in the source;
    * updates record changed fields only, with their originals; creates
      record the new attributes; deletes record the old ones — empty diffs
      write nothing;
    * globally redacted fields (`password`, `password_hash`,
      `remember_token`, `secret`, `api_key`, `token`) appear as
      `[redacted]`; the change is recorded, the value never is. Long
      strings truncate at #{2000} characters with an explicit marker;
    * `auditable_type` defaults to the Ecto schema module name; a schema
      that must match a Belimbing morph string defines
      `__audit_auditable_type__/0`;
    * Base Audit's own schemas are never captured, and further exclusions
      live in `:bilimbi_base_audit, :exclude_schemas` — the port of
      `audit.exclude_models`, one justified entry at a time.

  Rows are inserted synchronously in the caller's process, inside any open
  transaction: a rolled-back write rolls its audit row back with it. The
  seam guarantees a capture failure never fails the business write.
  """

  @behaviour Bilimbi.Base.Database.WriteCapture

  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Repo

  @redacted_fields ~w(password password_hash remember_token secret api_key token)a
  @redacted_marker "[redacted]"
  @truncate_at 2000
  @excluded_schemas [ActionSchema, MutationSchema]

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

  defp field_value(_field, value) when is_binary(value) do
    if String.length(value) > @truncate_at do
      String.slice(value, 0, @truncate_at) <>
        " [truncated #{String.length(value)} chars]"
    else
      value
    end
  end

  defp field_value(_field, %NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp field_value(_field, %DateTime{} = value), do: DateTime.to_iso8601(value)
  defp field_value(_field, %Date{} = value), do: Date.to_iso8601(value)
  defp field_value(_field, %Time{} = value), do: Time.to_iso8601(value)
  defp field_value(_field, value), do: value
end
