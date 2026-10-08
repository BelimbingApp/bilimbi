defmodule Bilimbi.Base.Schedule.Scheduler do
  @moduledoc false

  use GenServer
  import Ecto.Query
  require Logger

  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Administration
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Recurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.Suppression
  alias Ecto.Adapters.SQL
  alias Ecto.Multi

  @application :bilimbi_base_schedule
  @default_poll_interval 15_000
  @source "scheduler"
  @active_job_states [:available, :executing, :retryable, :scheduled]
  @reconcile_batch_size 300

  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl true
  def init(_options) do
    send(self(), :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    poll()
    Process.send_after(self(), :poll, poll_interval())
    {:noreply, state}
  end

  @doc false
  def poll(now \\ DateTime.utc_now()) do
    reconcile_terminal_occurrences()
    definitions = Administration.definitions()
    latest = latest_scheduled_occurrences(definitions)
    Enum.each(definitions, &enqueue_latest_due(&1, now, latest))
    :ok
  rescue
    error in ArgumentError ->
      Logger.warning(
        "schedule registry unavailable; recurrence poll skipped: #{Exception.message(error)}"
      )

      :ok
  catch
    :exit, _reason ->
      Logger.warning("schedule registry unavailable; recurrence poll skipped")
      :ok
  end

  @doc false
  @spec enqueue_due(Definition.t(), DateTime.t()) :: {:ok, Queue.JobRef.t()} | {:error, atom()}
  def enqueue_due(%Definition{} = definition, %DateTime{} = intended_at) do
    with {:error, :overlap} = refused <- enqueue_occurrence(definition, intended_at, :scheduled) do
      record_overlap(definition, intended_at, :scheduled, nil)
      refused
    end
  end

  @doc false
  def enqueue_occurrence(
        %Definition{} = definition,
        %DateTime{} = intended_at,
        trigger,
        opts \\ []
      )
      when trigger in [:manual, :scheduled] and is_list(opts) do
    intended_at = DateTime.truncate(intended_at, :microsecond)
    triggered_by = Keyword.get(opts, :triggered_by) || %{user_id: nil, name: nil}
    overlap_key = if definition.overlap == :forbid, do: @source <> ":" <> definition.key

    multi =
      Multi.new()
      |> Multi.run(:availability, fn _repo, _changes -> availability(definition) end)
      |> Multi.run(:claimable, fn _repo, _changes ->
        claimable(definition, intended_at, trigger, overlap_key)
      end)
      |> Multi.insert(
        :occurrence,
        Occurrence.claim_changeset(%{
          source: @source,
          key: definition.key,
          intended_at: intended_at,
          trigger: Atom.to_string(trigger),
          overlap_key: overlap_key,
          state: "queued",
          claimed_at: DateTime.utc_now()
        })
      )
      |> Queue.enqueue(:job, definition.worker, fn %{occurrence: occurrence} ->
        Map.put(definition.args, "__bilimbi_schedule__", %{
          "occurrence_id" => occurrence.id,
          "source" => @source,
          "key" => definition.key,
          "name" => definition.task_name,
          "expression" => if(trigger == :scheduled, do: definition.expression),
          "fingerprint" => Administration.fingerprint(definition),
          "intended_at" => DateTime.to_iso8601(intended_at),
          "trigger" => Atom.to_string(trigger),
          "triggered_by_user_id" => triggered_by.user_id,
          "triggered_by_name" => triggered_by.name
        })
      end)
      |> Multi.update(:record_job, fn %{occurrence: occurrence, job: job} ->
        Occurrence.job_changeset(occurrence, job.id)
      end)

    case Repo.transaction(multi) do
      {:ok, %{job: job}} ->
        {:ok, job}

      {:error, :availability, reason, _changes} ->
        {:error, reason}

      {:error, :claimable, :overlap, _changes} ->
        {:error, :overlap}

      {:error, :claimable, reason, _changes} ->
        {:error, reason}

      {:error, :occurrence, changeset, _changes} ->
        occurrence_error(changeset)

      {:error, :job, reason, _changes} ->
        {:error, reason}

      {:error, _operation, _reason, _changes} ->
        {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc false
  def reconcile_terminal_occurrences do
    from(item in Occurrence,
      where: is_nil(item.finished_at) and not is_nil(item.job_id),
      order_by: [asc: item.claimed_at, asc: item.id],
      limit: @reconcile_batch_size,
      select: {item.id, item.job_id}
    )
    |> Repo.all()
    |> reconcile_occurrences()
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc false
  def lock_key!(source, key) do
    SQL.query!(Repo.get_dynamic_repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      source <> ":" <> key
    ])

    :ok
  end

  @doc false
  def availability_after_lock(%Definition{} = definition) do
    review =
      Repo.one(
        from(item in DefinitionReview,
          where: item.source == @source and item.key == ^definition.key
        )
      )

    cond do
      is_nil(review) or review.fingerprint != Administration.fingerprint(definition) ->
        {:error, :unreviewed}

      not review.enabled ->
        {:error, :disabled}

      Repo.exists?(
        from(item in Suppression, where: item.source == @source and item.key == ^definition.key)
      ) ->
        {:error, :suppressed}

      true ->
        {:ok, :available}
    end
  end

  defp latest_scheduled_occurrences(definitions) do
    Administration.latest_scheduled_occurrences(Enum.map(definitions, & &1.key))
  rescue
    _error -> %{}
  catch
    :exit, _reason -> %{}
  end

  defp enqueue_latest_due(%Definition{} = definition, now, latest_occurrences) do
    case Recurrence.previous_occurrence(definition, now) do
      {:ok, local_intended} ->
        intended_at =
          DateTime.shift_zone!(local_intended, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)

        latest = Map.get(latest_occurrences, definition.key)

        if is_nil(latest) or DateTime.before?(latest, intended_at) do
          case enqueue_due(definition, intended_at) do
            {:ok, _job} ->
              :ok

            {:error, reason}
            when reason in [:already_claimed, :disabled, :overlap, :suppressed, :unreviewed] ->
              :ok

            {:error, reason} ->
              diagnostic(definition, reason)
          end
        end

      # previous_occurrence returns a specific reason — :invalid_timezone,
      # :invalid_expression (a misconfigured cron the schedule silently never
      # runs on), or :unresolvable_time (a DST edge). Collapsing them to a
      # generic :time_resolution_failed threw away the actionable half at the
      # source, the same defect #682 fixes at the sink; pass the real reason
      # through, keeping a generic fallback for any unexpected shape.
      {:error, reason} ->
        diagnostic(definition, reason)

      _other ->
        diagnostic(definition, :time_resolution_failed)
    end
  end

  # The reason is the actionable half. A plain-text sink (the LiveView console,
  # #682) renders only the message and drops metadata, so the reason and key go
  # in the message text; the structured fields stay for structured sinks. This
  # warning fires only for non-benign reasons (the benign five return :ok above),
  # so every occurrence is a real enqueue failure worth reading.
  defp diagnostic(definition, reason) do
    Logger.warning(
      "schedule occurrence was not enqueued: key=#{definition.key} reason=#{inspect(reason)}",
      schedule_key: definition.key,
      schedule_owner: definition.owner,
      schedule_reason: reason
    )
  end

  defp poll_interval do
    case Application.get_env(@application, :poll_interval, @default_poll_interval) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_poll_interval
    end
  end

  defp availability(definition) do
    lock_key!(@source, definition.key)
    availability_after_lock(definition)
  end

  defp occurrence_error(changeset) do
    names = Enum.map(changeset.constraints, & &1.constraint)

    cond do
      "base_schedule_occurrences_active_overlap_unique" in names -> {:error, :overlap}
      "base_schedule_occurrences_intended_unique" in names -> {:error, :already_claimed}
      true -> {:error, :unavailable}
    end
  end

  defp claimable(definition, intended_at, trigger, overlap_key) do
    with :ok <- reconcile_key(definition.key) do
      intended? =
        Repo.exists?(
          from(item in Occurrence,
            where:
              item.source == @source and item.key == ^definition.key and
                item.intended_at == ^intended_at and item.trigger == ^Atom.to_string(trigger)
          )
        )

      overlap? =
        overlap_key &&
          Repo.exists?(
            from(item in Occurrence,
              where: item.overlap_key == ^overlap_key and is_nil(item.finished_at)
            )
          )

      cond do
        intended? -> {:error, :already_claimed}
        overlap? -> {:error, :overlap}
        true -> {:ok, :claimable}
      end
    end
  end

  defp reconcile_key(key) do
    from(item in Occurrence,
      where:
        item.source == @source and item.key == ^key and is_nil(item.finished_at) and
          not is_nil(item.job_id),
      order_by: [asc: item.claimed_at, asc: item.id],
      limit: @reconcile_batch_size,
      select: {item.id, item.job_id}
    )
    |> Repo.all()
    |> reconcile_occurrences()
  end

  defp reconcile_occurrences(occurrences) do
    job_ids = occurrences |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    with {:ok, job_states} <- Queue.job_states(job_ids) do
      Enum.reduce_while(occurrences, :ok, fn {occurrence_id, job_id}, :ok ->
        case Map.fetch(job_states, job_id) do
          {:ok, state} when state in @active_job_states ->
            {:cont, :ok}

          {:ok, :completed} ->
            reconcile_occurrence(occurrence_id, "succeeded")
            {:cont, :ok}

          {:ok, state} when state in [:cancelled, :discarded] ->
            reconcile_occurrence(occurrence_id, "failed")
            {:cont, :ok}

          :error ->
            reconcile_occurrence(occurrence_id, "failed")
            {:cont, :ok}

          _unknown ->
            {:halt, {:error, :unavailable}}
        end
      end)
    end
  end

  defp reconcile_occurrence(occurrence_id, state) do
    Repo.update_all(
      from(item in Occurrence, where: item.id == ^occurrence_id and is_nil(item.finished_at)),
      set: [state: state, finished_at: DateTime.utc_now(), overlap_key: nil]
    )
  end

  @doc false
  def record_overlap(definition, intended_at, trigger, triggered_by) do
    triggered_by = triggered_by || %{user_id: nil, name: nil}
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert!(%Run{
      source: @source,
      key: definition.key,
      name: definition.task_name,
      expression: if(trigger == :scheduled, do: definition.expression),
      trigger: Atom.to_string(trigger),
      triggered_by_user_id: triggered_by.user_id,
      triggered_by_name: triggered_by.name,
      status: "skipped",
      started_at: DateTime.to_naive(intended_at) |> NaiveDateTime.truncate(:second),
      finished_at: now,
      runtime_ms: 0,
      output_excerpt: "overlap"
    })
  rescue
    _error -> overlap_recording_failed(definition)
  catch
    :exit, _reason -> overlap_recording_failed(definition)
  end

  defp overlap_recording_failed(definition) do
    Logger.warning("schedule overlap history recording unavailable",
      schedule_source: @source,
      schedule_key: definition.key
    )

    {:error, :recording_unavailable}
  end
end
