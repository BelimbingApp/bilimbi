defmodule Bilimbi.Base.Audit.ConsoleCapture do
  @moduledoc """
  Records every database console command as an audit action.

  The console is a developer tool on the application's own database
  connection, with no login of its own. What it refuses is a write; what
  it records is everything. The record, not a restriction, is the control:
  it exists so that a command run through a developer's stolen or hijacked
  session is told apart from the developer's own work by where it came
  from, what client sent it, and when.

  Base Database's `ConsoleCapture` seam calls `after_console_command/3`
  after every command, whatever its outcome. Each call writes exactly one
  `base_audit_actions` row:

    * the actor pair, role, company, tenant, `impersonator_id`,
      `ip_address`, `url`, `user_agent`, and `trace_id` come from the
      per-process `Bilimbi.Base.Audit.Context`, which the web edge fills
      per request and per LiveView mount. Absent context records the
      guest default, never nothing;
    * the event names the outcome: `database_query.executed` for a command
      that ran, `database_query.refused` for one a guard stopped,
      `database_query.failed` for one the database rejected;
    * the payload carries the SQL **as typed**, bounded by
      `Bilimbi.Base.Audit.PayloadText`, the saved query's name when the
      caller gave one, and the outcome: the matched row count, the guard
      and its message, or the database's error message. Result rows never
      reach this module.

  Rows are inserted synchronously in the caller's process, after the
  executor's read-only transaction has ended — a `READ ONLY` transaction
  could not hold the row itself. They are not retained by default, like
  every other recorded action.
  """

  @behaviour Bilimbi.Base.Database.ConsoleCapture

  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.PayloadText
  alias Bilimbi.Base.Repo

  @impl true
  def after_console_command(sql, outcome, meta) when is_binary(sql) and is_map(meta) do
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
      trace_id: bounded(context.trace_id, 12),
      event: event(outcome),
      payload: payload(sql, outcome, meta),
      is_retained: false,
      occurred_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }
    |> ActionSchema.changeset(context.tenant_id)
    |> Repo.insert!()

    :ok
  end

  defp event({:succeeded, _count}), do: "database_query.executed"
  defp event({:refused, _guard, _message}), do: "database_query.refused"
  defp event({:failed, _message}), do: "database_query.failed"

  defp payload(sql, outcome, meta) do
    %{"sql" => PayloadText.bounded(sql)}
    |> put_name(meta)
    |> Map.merge(outcome_payload(outcome))
  end

  defp put_name(payload, %{name: name}) when is_binary(name),
    do: Map.put(payload, "name", PayloadText.bounded(name))

  defp put_name(payload, _meta), do: payload

  defp outcome_payload({:succeeded, count}),
    do: %{"result" => "succeeded", "row_count" => count}

  defp outcome_payload({:refused, guard, message}),
    do: %{
      "result" => "refused",
      "guard" => Atom.to_string(guard),
      "message" => PayloadText.bounded(message)
    }

  defp outcome_payload({:failed, message}),
    do: %{"result" => "failed", "message" => PayloadText.bounded(message)}

  defp bounded(nil, _max), do: nil
  defp bounded(value, max) when is_binary(value), do: String.slice(value, 0, max)
end
