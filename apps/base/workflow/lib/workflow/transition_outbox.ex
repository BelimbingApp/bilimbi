defmodule Bilimbi.Base.Workflow.TransitionOutbox do
  @moduledoc false
  # Durable, at-least-once delivery of committed transitions on Belimbing's
  # `base_workflow_transition_outbox` rows: one row per transition fact keyed
  # by its history id, written in the transition's own transaction; a short
  # database lease per attempt; exponential backoff with the failure kept in
  # `last_error`; `delivered_at` once every registered listener accepted the
  # event. Retained Belimbing rows are delivered by the same path: the tenant
  # and subject come from the proven subject binding, never from the row's
  # own claims, so an unadopted legacy row is deferred, not guessed.
  import Ecto.Query
  require Logger

  alias Bilimbi.Base.{Queue, Repo, Tenancy}
  alias Bilimbi.Base.Tenancy.Scope

  alias Bilimbi.Base.Workflow.{
    Attribution,
    BindingSchema,
    Definitions,
    DeliveryWorker,
    JSON,
    OutboxSchema
  }

  @event_type "workflow.transition.completed"
  @lease_seconds 300
  @error_limit 4000

  # Runs inside the transition transaction, after the history row exists. The
  # immediate delivery job is inserted in that same transaction, so a refused
  # transition leaves neither a row nor a job, and a committed one is
  # attempted right after commit without any process-level after-commit hook.
  def enqueue(scope, ref, flow, subject, stored_edge, history, context) do
    time = now()

    with {:ok, payload} <- payload(scope, ref, flow, subject, stored_edge, history, context),
         {:ok, row} <-
           Repo.insert(%OutboxSchema{
             event_key: "#{@event_type}:#{history.id}",
             event_type: @event_type,
             payload: payload,
             attempts: 0,
             available_at: time,
             created_at: time,
             updated_at: time
           }) do
      schedule_immediate(row.id)
      {:ok, %{id: row.id, event_key: row.event_key}}
    end
  end

  # Delivers one row now when it is due and unleased: `{:ok, :delivered}`,
  # `{:ok, :deferred}` (a listener refused; the row waits for its backoff) or
  # `{:ok, :skipped}` (delivered already, not yet due, leased, or missing).
  def deliver(id) when is_integer(id) and id > 0 do
    token = Ecto.UUID.generate()

    case claim(id, token) do
      nil -> {:ok, :skipped}
      row -> settle(row, token, attempt(row))
    end
  end

  def deliver(_id), do: {:error, :invalid_outbox_id}

  def deliver_due(opts) do
    opts = Keyword.validate!(opts, limit: 100)
    limit = opts[:limit]

    unless is_integer(limit) and limit in 1..1000,
      do: raise(ArgumentError, "outbox delivery limit must be 1..1000")

    time = now()

    ids =
      Repo.all(
        from(o in OutboxSchema,
          where:
            is_nil(o.delivered_at) and o.available_at <= ^time and
              (is_nil(o.lease_token) or o.lease_expires_at <= ^time),
          order_by: [asc: o.id],
          limit: ^limit,
          select: o.id
        )
      )

    summary =
      Enum.reduce(ids, %{delivered: 0, deferred: 0, skipped: 0}, fn id, acc ->
        {:ok, outcome} = deliver(id)
        Map.update!(acc, outcome, &(&1 + 1))
      end)

    {:ok, summary}
  end

  defp payload(scope, ref, flow, subject, stored_edge, history, context) do
    actor = Scope.actor(scope)
    attrs = Map.take(context, [:comment, :comment_tag, :assignees, :attachments, :metadata])

    facts = %{
      "flow" => ref.flow,
      "flow_model" => flow.model_class,
      "flow_id" => ref.id,
      "from_status" => subject.status,
      "to_status" => history.status,
      "actor_id" => actor.user_id,
      "actor_role" => nil,
      "actor_department" => nil,
      "assignees" => attrs[:assignees],
      "comment" => attrs[:comment],
      "comment_tag" => attrs[:comment_tag],
      "attachments" => attrs[:attachments],
      "metadata" => attrs[:metadata],
      "transitioned_at" => iso8601(history.transitioned_at)
    }

    payload = %{
      "model_class" => flow.model_class,
      "model_id" => ref.id,
      "model_key_name" => "id",
      "model_snapshot" => nil,
      "subject_type" => ref.type,
      "tenant_id" => Scope.tenant_id(scope),
      "company_id" => subject.company_id,
      "transition_id" => stored_edge.id,
      "transition_snapshot" => snapshot(stored_edge),
      "history_id" => history.id,
      "history_snapshot" => snapshot(history),
      "context" => %{
        "actor" => %{
          "type" => Atom.to_string(actor.type),
          "id" => actor.user_id,
          "company_id" => actor.company_id,
          "impersonator_id" => actor.impersonator_id,
          "system_principal" => actor.system_principal
        },
        "comment" => attrs[:comment],
        "comment_tag" => attrs[:comment_tag],
        "assignees" => attrs[:assignees],
        "attachments" => attrs[:attachments],
        "metadata" => attrs[:metadata]
      },
      "payload" => facts
    }

    case JSON.cast(payload) do
      {:ok, payload} -> {:ok, payload}
      :error -> {:error, :invalid_event_payload}
    end
  end

  # A missing immediate attempt is not a lost event: the maintenance schedule
  # delivers every due row. The warning names the row so the gap is visible.
  defp schedule_immediate(id) do
    case Queue.enqueue(DeliveryWorker, %{"outbox_id" => id}) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "workflow transition event #{id} waits for the maintenance schedule: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp claim(id, token) do
    {:ok, row} =
      Repo.transact(fn ->
        time = now()

        case Repo.one(from(o in OutboxSchema, where: o.id == ^id, lock: "FOR UPDATE")) do
          %OutboxSchema{delivered_at: nil} = row ->
            cond do
              NaiveDateTime.compare(row.available_at, time) == :gt ->
                {:ok, nil}

              live_lease?(row, time) ->
                {:ok, nil}

              true ->
                {:ok,
                 update!(row, %{
                   attempts: row.attempts + 1,
                   lease_token: token,
                   lease_expires_at: NaiveDateTime.add(time, @lease_seconds),
                   updated_at: time
                 })}
            end

          _delivered_or_missing ->
            {:ok, nil}
        end
      end)

    row
  end

  defp live_lease?(%{lease_token: token, lease_expires_at: expires}, time),
    do: not is_nil(token) and not is_nil(expires) and NaiveDateTime.compare(expires, time) == :gt

  # Anything that escapes a listener defers the row with its message, as
  # Belimbing's dispatcher caught every Throwable; the lease stays short.
  defp attempt(row) do
    case resolve(row) do
      {:ok, scope, ref, event} -> dispatch(scope, ref, event)
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp settle(row, token, :ok) do
    time = now()

    _ =
      Repo.update_all(leased(row, token),
        set: [
          delivered_at: time,
          lease_token: nil,
          lease_expires_at: nil,
          last_error: nil,
          updated_at: time
        ]
      )

    {:ok, :delivered}
  end

  defp settle(row, token, {:error, reason}) do
    time = now()
    delay = min(3600, Integer.pow(2, min(10, row.attempts)))

    _ =
      Repo.update_all(leased(row, token),
        set: [
          available_at: NaiveDateTime.add(time, delay),
          lease_token: nil,
          lease_expires_at: nil,
          last_error: describe(reason),
          updated_at: time
        ]
      )

    {:ok, :deferred}
  end

  defp leased(row, token),
    do: from(o in OutboxSchema, where: o.id == ^row.id and o.lease_token == ^token)

  # The proven binding names the tenant, subject and owner of a (flow, flow_id);
  # a row's own payload is never believed for any of them.
  defp resolve(%OutboxSchema{payload: %{"payload" => %{"flow" => flow} = facts} = payload} = row)
       when is_binary(flow) do
    with {:ok, flow_id} <- Definitions.numeric_id(Map.get(facts, "flow_id")),
         %BindingSchema{} = binding <- binding(flow, flow_id),
         {:ok, ref} <- Definitions.subject(%{type: binding.subject_type, id: binding.subject_id}),
         :ok <- same_owner(ref, binding, flow),
         {:ok, scope} <- Tenancy.scope(binding.tenant_id) do
      {:ok, scope, ref, event(row, ref, payload)}
    else
      nil -> {:error, :subject_unbound}
      :error -> {:error, :invalid_event_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve(_row), do: {:error, :invalid_event_payload}

  # Cross-tenant by design: the binding is what tells us the tenant.
  defp binding(flow, flow_id),
    do: Repo.one(from(b in BindingSchema, where: b.flow == ^flow and b.flow_id == ^flow_id))

  defp same_owner(ref, binding, flow) do
    cond do
      ref.owner != binding.owner -> {:error, :subject_binding_conflict}
      ref.flow != flow -> {:error, :flow_unavailable}
      true -> :ok
    end
  end

  defp event(row, ref, payload) do
    facts = Map.get(payload, "payload") || %{}
    history = Map.get(payload, "history_snapshot") || %{}
    context = Map.get(payload, "context") || %{}
    actor = Map.get(context, "actor") || %{}

    %{
      event_key: row.event_key,
      event_type: row.event_type,
      subject: %{type: ref.type, id: ref.id},
      flow: Map.get(facts, "flow"),
      from_status: Map.get(facts, "from_status"),
      to_status: Map.get(facts, "to_status"),
      transition: Map.get(payload, "transition_snapshot") || %{},
      history: history,
      actor: %{
        type: Map.get(history, "actor_type") || Map.get(actor, "type"),
        id: Map.get(history, "actor_id") || Map.get(facts, "actor_id")
      },
      context: %{
        comment: Map.get(facts, "comment"),
        comment_tag: Map.get(facts, "comment_tag"),
        assignees: Map.get(facts, "assignees"),
        attachments: Map.get(facts, "attachments"),
        metadata: Map.get(facts, "metadata")
      },
      transitioned_at: parse_time(Map.get(facts, "transitioned_at")),
      attempt: row.attempts
    }
  end

  defp dispatch(scope, ref, event) do
    listeners =
      Definitions.registry!().transition_listeners
      |> Map.values()
      |> Enum.filter(&(ref.type in &1.subjects))
      |> Enum.sort_by(& &1.key)

    Attribution.attributed(scope, fn ->
      Enum.reduce_while(listeners, :ok, fn listener, :ok ->
        case invoke(listener, scope, event) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {listener.key, reason}}}
        end
      end)
    end)
  end

  defp invoke(listener, scope, event) do
    case listener.adapter.handle(scope, event) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_listener_result, other}}
    end
  end

  defp describe(reason), do: reason |> inspect(limit: 50) |> String.slice(0, @error_limit)

  defp snapshot(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), json_value(value)} end)
  end

  defp json_value(%NaiveDateTime{} = time), do: iso8601(time)
  defp json_value(value), do: value

  defp iso8601(%NaiveDateTime{} = time),
    do: time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      _ -> nil
    end
  end

  defp parse_time(_value), do: nil

  defp update!(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
