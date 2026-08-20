defmodule Bilimbi.Base.Schedule do
  @moduledoc """
  Deterministic recurrence registration and Queue-backed occurrence claiming.

  Definitions are immutable installed-module contributions. Every new or
  materially changed definition is disabled until its fingerprint is reviewed.
  Downtime uses coalescing: at most the latest missed occurrence is enqueued.
  """

  import Ecto.Query

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Suppression
  alias Ecto.Adapters.SQL
  alias Ecto.Multi

  @source "scheduler"

  @spec definitions() :: [Definition.t()]
  def definitions do
    ContributionRegistry.consumer!(:schedule)
    |> Map.values()
    |> Enum.sort_by(&{&1.owner, &1.key})
  end

  @spec definition(String.t()) :: Definition.t() | nil
  def definition(key) when is_binary(key),
    do: Map.get(ContributionRegistry.consumer!(:schedule), key)

  def definition(_key), do: nil

  @doc "Reviews the current definition fingerprint and explicitly enables or disables it."
  @spec review_definition(String.t(), boolean()) :: :ok | {:error, :not_found | :unavailable}
  def review_definition(key, enabled) when is_binary(key) and is_boolean(enabled) do
    with %Definition{} = definition <- definition(key) do
      Repo.transaction(fn ->
        lock_key!(@source, key)

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
    else
      nil -> {:error, :not_found}
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
    with %Definition{} = definition <- definition(key) do
      Repo.transaction(fn ->
        lock_key!(@source, key)

        Repo.insert!(%Suppression{source: @source, key: key, name: definition.task_name},
          on_conflict: {:replace, [:name, :updated_at]},
          conflict_target: [:source, :key]
        )
      end)

      :ok
    else
      nil -> {:error, :not_found}
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
    with %Definition{} <- definition(key) do
      Repo.transaction(fn ->
        lock_key!(@source, key)

        Repo.delete_all(
          from(item in Suppression, where: item.source == @source and item.key == ^key)
        )
      end)

      :ok
    else
      nil -> {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def resume(_key), do: {:error, :not_found}

  @doc "Queues one operator-requested occurrence; execution is never inline."
  @spec run_now(String.t()) :: {:ok, Queue.JobRef.t()} | {:error, atom()}
  def run_now(key) when is_binary(key) do
    with %Definition{} = definition <- definition(key) do
      enqueue_occurrence(definition, DateTime.utc_now(), :manual)
    else
      nil -> {:error, :not_found}
    end
  end

  def run_now(_key), do: {:error, :not_found}

  @doc false
  @spec enqueue_due(Definition.t(), DateTime.t()) :: {:ok, Queue.JobRef.t()} | {:error, atom()}
  def enqueue_due(%Definition{} = definition, %DateTime{} = intended_at) do
    enqueue_occurrence(definition, intended_at, :scheduled)
  end

  @doc false
  def latest_scheduled_occurrence(%Definition{} = definition) do
    Repo.one(
      from(item in Occurrence,
        where:
          item.source == @source and item.key == ^definition.key and item.trigger == "scheduled",
        select: max(item.intended_at)
      )
    )
  rescue
    _error -> nil
  catch
    :exit, _reason -> nil
  end

  @doc false
  def fingerprint(%Definition{} = definition) do
    worker_id = definition.worker.__queue_worker__().id

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({
        definition.key,
        definition.name,
        definition.expression,
        definition.timezone,
        definition.owner,
        definition.task_name,
        worker_id,
        definition.args,
        definition.overlap,
        definition.misfire
      })
    )
    |> Base.encode16(case: :lower)
  end

  defp enqueue_occurrence(definition, intended_at, trigger) do
    intended_at = DateTime.truncate(intended_at, :microsecond)
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
          "intended_at" => DateTime.to_iso8601(intended_at),
          "trigger" => Atom.to_string(trigger)
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
        best_effort_record_overlap(definition, intended_at, trigger)
        {:error, :overlap}

      {:error, :claimable, reason, _changes} ->
        {:error, reason}

      {:error, :occurrence, changeset, _changes} ->
        case occurrence_error(changeset) do
          {:error, :overlap} = error ->
            best_effort_record_overlap(definition, intended_at, trigger)
            error

          error ->
            error
        end

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

  defp availability(definition) do
    lock_key!(@source, definition.key)

    review =
      Repo.one(
        from(item in DefinitionReview,
          where: item.source == @source and item.key == ^definition.key
        )
      )

    cond do
      is_nil(review) or review.fingerprint != fingerprint(definition) ->
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

  defp occurrence_error(changeset) do
    names = Enum.map(changeset.constraints, & &1.constraint)

    cond do
      "base_schedule_occurrences_active_overlap_unique" in names -> {:error, :overlap}
      "base_schedule_occurrences_intended_unique" in names -> {:error, :already_claimed}
      true -> {:error, :unavailable}
    end
  end

  defp claimable(definition, intended_at, trigger, overlap_key) do
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

  defp best_effort_record_overlap(definition, intended_at, trigger) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert!(%Bilimbi.Base.Schedule.Run{
      source: @source,
      key: definition.key,
      name: definition.task_name,
      expression: if(trigger == :scheduled, do: definition.expression),
      status: "skipped",
      started_at: DateTime.to_naive(intended_at) |> NaiveDateTime.truncate(:second),
      finished_at: now,
      runtime_ms: 0,
      output_excerpt: "overlap"
    })
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp lock_key!(source, key) do
    SQL.query!(Repo.get_dynamic_repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      source <> ":" <> key
    ])

    :ok
  end
end
