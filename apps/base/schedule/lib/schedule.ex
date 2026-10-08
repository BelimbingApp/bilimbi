defmodule Bilimbi.Base.Schedule do
  @moduledoc """
  Deterministic recurrence registration and Queue-backed occurrence claiming.

  Definitions are immutable installed-module contributions. Every new or
  materially changed definition is disabled until its fingerprint is reviewed.
  Downtime uses coalescing: at most the latest missed occurrence is enqueued.
  """

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.PrincipalDirectory
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Administration
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Diagnostics
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.RunPage
  alias Bilimbi.Base.Schedule.Scheduler
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TaskSummary
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Tenancy.Actor, as: TenancyActor
  alias Bilimbi.Base.Tenancy.Scope

  @source "scheduler"
  @retention_key "schedule.history.keep_days"
  @execute "admin.system.schedule.execute"
  @manage "admin.system.schedule.manage"

  @spec definitions() :: [Definition.t()]
  def definitions, do: Administration.definitions()

  @spec definition(String.t()) :: Definition.t() | nil
  def definition(key), do: Administration.definition(key)

  @doc "Returns filtered operator-facing schedule facts without worker arguments."
  @spec list_tasks(keyword()) ::
          {:ok, [TaskSummary.t()]} | {:error, :invalid_options | :unavailable}
  def list_tasks(options \\ [])
  def list_tasks(options), do: Administration.list_tasks(options)

  @doc """
  Returns an exact, database-filtered page of redacted run history.

  `start_date` and `end_date` select whole calendar days of `started_at` in
  `timezone`, an IANA zone name that defaults to `UTC`. A caller passes the
  zone it displays the rows in, so a run shown on a day is selected by that
  day; an unknown zone is `{:error, :invalid_options}`.
  """
  @spec list_runs(keyword()) ::
          {:ok, RunPage.t()} | {:error, :invalid_options | :unavailable}
  def list_runs(options \\ [])
  def list_runs(options), do: Administration.list_runs(options)

  @doc "Reports scheduler, Queue, recorder, and due-work evidence independently."
  @spec diagnostics() :: Diagnostics.t()
  def diagnostics do
    queue_diagnostics = Queue.diagnostics()
    queue = if queue_diagnostics.available?, do: :available, else: :unavailable
    recorder = recorder_availability()

    %Diagnostics{
      scheduler: scheduler_availability(),
      queue: queue,
      recorder: recorder,
      due_work: Administration.due_work_state()
    }
  end

  defp scheduler_availability do
    if Process.whereis(Scheduler), do: :available, else: :unavailable
  end

  @doc """
  Reviews one immutable definition and records who decided.

  The caller is the sealed scope. Manage is the capability the schedule board
  already requires for this command. A system actor names nobody and is refused.
  """
  @spec review_definition(Scope.t(), String.t(), boolean()) ::
          :ok | {:error, :audit_unavailable | :forbidden | :not_found | :unavailable}
  def review_definition(%Scope{} = scope, key, enabled)
      when is_binary(key) and is_boolean(enabled) do
    event = if enabled, do: "schedule.task.enabled", else: "schedule.task.disabled"

    with :ok <- authorize(scope, @manage) do
      operator_action(scope, event, key, %{"enabled" => enabled}, fn ->
        review_definition(key, enabled)
      end)
    end
  end

  def review_definition(%Scope{} = scope, _key, _enabled) do
    with :ok <- authorize(scope, @manage), do: {:error, :not_found}
  end

  @doc """
  Pauses a definition and records the action in the same transaction.

  Requires the manage capability the schedule board already uses.
  """
  @spec suppress(Scope.t(), String.t()) ::
          :ok | {:error, :audit_unavailable | :forbidden | :not_found | :unavailable}
  def suppress(%Scope{} = scope, key) when is_binary(key) do
    with :ok <- authorize(scope, @manage) do
      operator_action(scope, "schedule.task.paused", key, %{}, fn -> suppress(key) end)
    end
  end

  def suppress(%Scope{} = scope, _key) do
    with :ok <- authorize(scope, @manage), do: {:error, :not_found}
  end

  @doc """
  Resumes a definition and records the action in the same transaction.

  Requires the manage capability the schedule board already uses.
  """
  @spec resume(Scope.t(), String.t()) ::
          :ok | {:error, :audit_unavailable | :forbidden | :not_found | :unavailable}
  def resume(%Scope{} = scope, key) when is_binary(key) do
    with :ok <- authorize(scope, @manage) do
      operator_action(scope, "schedule.task.resumed", key, %{}, fn -> resume(key) end)
    end
  end

  def resume(%Scope{} = scope, _key) do
    with :ok <- authorize(scope, @manage), do: {:error, :not_found}
  end

  @doc """
  Queues run-now and records who queued it in the same transaction.

  Requires the execute capability the schedule board already uses. Execution
  stays on the queue.
  """
  @spec run_now(Scope.t(), String.t()) ::
          {:ok, Queue.JobRef.t()} | {:error, atom()}
  def run_now(%Scope{} = scope, key) when is_binary(key) do
    with :ok <- authorize(scope, @execute) do
      triggered_by = triggered_by(scope)

      scope
      |> operator_action("schedule.run.queued", key, %{}, fn ->
        enqueue_manual(key, triggered_by)
      end)
      |> record_refused_overlap(key, triggered_by)
    end
  end

  def run_now(%Scope{} = scope, _key) do
    with :ok <- authorize(scope, @execute), do: {:error, :not_found}
  end

  @doc """
  Changes global history retention and records who changed it.

  Requires the manage capability the schedule board already uses.
  """
  @spec set_history_retention(Scope.t(), integer()) ::
          {:ok, integer()}
          | {:error, :audit_unavailable | :forbidden | :invalid_retention | :unavailable}
  def set_history_retention(%Scope{} = scope, days) when is_integer(days) do
    with :ok <- authorize(scope, @manage) do
      if history_retention?(days) do
        put_history_retention(scope, days)
      else
        {:error, :invalid_retention}
      end
    end
  end

  def set_history_retention(%Scope{} = scope, _days) do
    with :ok <- authorize(scope, @manage), do: {:error, :invalid_retention}
  end

  defp history_retention?(days) do
    Settings.Definition.accepts?(Settings.definition!(@retention_key), days)
  end

  defp put_history_retention(%Scope{} = scope, days) do
    operator_action(
      scope,
      "schedule.retention.changed",
      @retention_key,
      %{"days" => days},
      fn ->
        case Settings.put(@retention_key, days) do
          {:ok, value} -> {:ok, value}
          {:error, _changeset} -> {:error, :unavailable}
        end
      end
    )
  end

  @doc "Reviews the current definition fingerprint and explicitly enables or disables it."
  @spec review_definition(String.t(), boolean()) :: :ok | {:error, :not_found | :unavailable}
  def review_definition(key, enabled) when is_binary(key) and is_boolean(enabled) do
    case definition(key) do
      %Definition{} = definition ->
        Repo.transaction(fn ->
          Scheduler.lock_key!(@source, key)

          attributes = %{
            source: @source,
            key: key,
            fingerprint: fingerprint(definition),
            enabled: enabled,
            reviewed_at: DateTime.utc_now()
          }

          %DefinitionReview{}
          |> DefinitionReview.changeset(attributes)
          |> Repo.insert!(
            on_conflict: {:replace, [:fingerprint, :enabled, :reviewed_at]},
            conflict_target: [:source, :key]
          )
        end)

        :ok

      nil ->
        {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def review_definition(_key, _enabled), do: {:error, :not_found}

  @doc "Suppresses a reviewed definition. A suppression row always means paused."
  @spec suppress(String.t()) :: :ok | {:error, :not_found | :unavailable}
  def suppress(key) when is_binary(key) do
    case definition(key) do
      %Definition{} = definition ->
        Repo.transaction(fn ->
          Scheduler.lock_key!(@source, key)

          Repo.insert!(%Suppression{source: @source, key: key, name: definition.task_name},
            on_conflict: {:replace, [:name, :updated_at]},
            conflict_target: [:source, :key]
          )
        end)

        :ok

      nil ->
        {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def suppress(_key), do: {:error, :not_found}

  @doc "Removes the suppression for a registered definition."
  @spec resume(String.t()) :: :ok | {:error, :not_found | :unavailable}
  def resume(key) when is_binary(key) do
    case definition(key) do
      %Definition{} ->
        Repo.transaction(fn ->
          Scheduler.lock_key!(@source, key)

          Repo.delete_all(
            from(item in Suppression, where: item.source == @source and item.key == ^key)
          )
        end)

        :ok

      nil ->
        {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def resume(_key), do: {:error, :not_found}

  @doc """
  Queues one operator-requested occurrence; execution is never inline.

  Without a scope nobody is named for the run: history shows "Run now" with
  no person. `run_now/2` is the form that records who asked.
  """
  @spec run_now(String.t()) :: {:ok, Queue.JobRef.t()} | {:error, atom()}
  def run_now(key) when is_binary(key),
    do: key |> enqueue_manual(nil) |> record_refused_overlap(key, nil)

  def run_now(_key), do: {:error, :not_found}

  # A refused run is history too. It is written here, after any operator
  # transaction has rolled back, so the refusal that rolls it back cannot
  # discard the row naming who asked.
  defp record_refused_overlap({:error, :overlap} = refused, key, triggered_by) do
    case definition(key) do
      %Definition{} = definition ->
        Scheduler.record_overlap(definition, DateTime.utc_now(), :manual, triggered_by)

      nil ->
        :ok
    end

    refused
  rescue
    _error -> {:error, :overlap}
  catch
    :exit, _reason -> {:error, :overlap}
  end

  defp record_refused_overlap(result, _key, _triggered_by), do: result

  defp enqueue_manual(key, triggered_by) do
    case definition(key) do
      %Definition{} = definition ->
        Scheduler.enqueue_occurrence(definition, DateTime.utc_now(), :manual,
          triggered_by: triggered_by
        )

      nil ->
        {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  # Who clicked Run now, captured at dispatch: the user's id from the sealed
  # actor, and the display name the principal directory gives that id in this
  # tenant. The name is denormalised onto the run so history never needs a
  # Base-to-Core read; a name the directory cannot resolve stays nil and the
  # id still identifies the person.
  defp triggered_by(%Scope{} = scope) do
    case Scope.actor(scope) do
      %TenancyActor{type: :user, user_id: user_id} ->
        %{user_id: user_id, name: principal_name(scope, user_id)}

      %TenancyActor{} ->
        nil
    end
  end

  # The name is best effort: an installation whose directory names no users
  # still queues the run, recorded by id alone.
  defp principal_name(%Scope{} = scope, user_id) do
    case PrincipalDirectory.rank(scope, [{:user, user_id}]) do
      {:ok, [%{name: name}]} when is_binary(name) and name != "" -> String.slice(name, 0, 255)
      _unresolved -> nil
    end
  rescue
    _no_directory -> nil
  end

  @doc false
  @spec latest_scheduled_occurrences([String.t()]) :: %{optional(String.t()) => DateTime.t()}
  def latest_scheduled_occurrences(keys),
    do: Administration.latest_scheduled_occurrences(keys)

  @doc false
  @spec authorize_execution(map(), pos_integer()) :: {:ok, struct()} | {:error, term()}
  def authorize_execution(metadata, job_id)
      when is_map(metadata) and is_integer(job_id) and job_id > 0 do
    current_definition = definition(metadata["key"])

    case Repo.transaction(fn ->
           Scheduler.lock_key!(metadata["source"], metadata["key"])
           authorize_execution_locked(current_definition, metadata, job_id)
         end) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc false
  @spec fingerprint(Definition.t()) :: String.t()
  def fingerprint(definition), do: Administration.fingerprint(definition)

  @doc "Prunes completed occurrence history older than the configured retention period."
  @spec prune_occurrences() :: non_neg_integer()
  def prune_occurrences do
    case Settings.get(@retention_key) do
      0 ->
        0

      days ->
        cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

        latest =
          from(item in Occurrence,
            where: item.trigger == "scheduled",
            distinct: [item.source, item.key],
            order_by: [asc: item.source, asc: item.key, desc: item.intended_at],
            select: item.id
          )

        {count, _rows} =
          Repo.delete_all(
            from(item in Occurrence,
              where: not is_nil(item.finished_at) and item.finished_at < ^cutoff,
              where: item.id not in subquery(latest)
            )
          )

        count
    end
  end

  defp recorder_availability do
    _ = Repo.one(from(run in Run, select: 1, limit: 1))
    :available
  rescue
    _error -> :unavailable
  catch
    :exit, _reason -> :unavailable
  end

  # The board's `can_*` assigns only decide which controls to draw. These
  # commands are the authority: each one asks Authz with the scope the edge
  # sealed, using the capability that screen already uses. An anonymous system
  # actor has no grant and is refused. The scheduler enqueues with
  # `Scheduler.enqueue_due/2`, not these commands.
  defp authorize(%Scope{} = scope, capability) do
    case Authz.can(scope, capability) do
      %{allowed: true} -> :ok
      %{allowed: false} -> {:error, :forbidden}
    end
  end

  defp operator_action(%Scope{} = scope, event, key, payload, operation) do
    case Repo.transaction(fn ->
           case operation.() do
             {:error, reason} ->
               Repo.rollback(reason)

             result ->
               case record_operator_action(scope, event, key, payload) do
                 {:ok, _action} -> result
                 {:error, _reason} -> Repo.rollback(:audit_unavailable)
               end
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp record_operator_action(%Scope{} = scope, event, key, payload) do
    actor = Scope.actor(scope)

    Audit.record_action(scope, %{
      company_id: actor.company_id,
      actor_type: Atom.to_string(actor.type),
      actor_id: actor.user_id || 0,
      impersonator_id: actor.impersonator_id,
      system_principal: actor.system_principal,
      event: event,
      payload: Map.merge(%{"source" => @source, "key" => key}, payload),
      occurred_at: NaiveDateTime.utc_now()
    })
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp authorize_execution_locked(nil, metadata, job_id) do
    cancel_execution_occurrence(metadata, job_id, :not_found)
  end

  defp authorize_execution_locked(definition, metadata, job_id) do
    if fingerprint(definition) != metadata["fingerprint"] do
      cancel_execution_occurrence(metadata, job_id, :changed)
    else
      case Scheduler.availability_after_lock(definition) do
        {:ok, :available} -> claim_execution_occurrence(metadata, job_id)
        {:error, reason} -> cancel_execution_occurrence(metadata, job_id, reason)
      end
    end
  end

  defp claim_execution_occurrence(metadata, job_id) do
    query = execution_occurrence_query(metadata, job_id)

    case Repo.one(query) do
      %Occurrence{} = occurrence ->
        case Repo.update_all(query, set: [state: "running", started_at: DateTime.utc_now()]) do
          {1, _rows} -> {:ok, occurrence}
          _not_updated -> {:error, :not_found}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp cancel_execution_occurrence(metadata, job_id, reason) do
    case Repo.update_all(execution_occurrence_query(metadata, job_id),
           set: [state: "failed", finished_at: DateTime.utc_now(), overlap_key: nil]
         ) do
      {1, _rows} -> {:error, {:cancel, unavailable_code(reason)}}
      _not_updated -> {:error, :not_found}
    end
  end

  defp execution_occurrence_query(metadata, job_id) do
    {:ok, intended_at, 0} = DateTime.from_iso8601(metadata["intended_at"])

    from(item in Occurrence,
      where:
        item.id == ^metadata["occurrence_id"] and item.source == ^metadata["source"] and
          item.key == ^metadata["key"] and item.intended_at == ^intended_at and
          item.trigger == ^metadata["trigger"] and item.job_id == ^job_id and
          is_nil(item.finished_at)
    )
  end

  defp unavailable_code(:disabled), do: :schedule_disabled
  defp unavailable_code(:suppressed), do: :schedule_suppressed
  defp unavailable_code(:unreviewed), do: :schedule_unreviewed
  defp unavailable_code(:changed), do: :schedule_changed
  defp unavailable_code(:not_found), do: :schedule_removed
  defp unavailable_code(_reason), do: :schedule_unavailable
end
