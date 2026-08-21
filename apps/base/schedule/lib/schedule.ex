defmodule Bilimbi.Base.Schedule do
  @moduledoc """
  Deterministic recurrence registration and Queue-backed occurrence claiming.

  Definitions are immutable installed-module contributions. Every new or
  materially changed definition is disabled until its fingerprint is reviewed.
  Downtime uses coalescing: at most the latest missed occurrence is enqueued.
  """

  import Ecto.Query
  require Logger

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Diagnostics
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Recurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.RunPage
  alias Bilimbi.Base.Schedule.RunSummary
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TaskSummary
  alias Bilimbi.Base.Settings
  alias Ecto.Adapters.SQL
  alias Ecto.Multi

  @source "scheduler"
  @active_job_states [:available, :executing, :retryable, :scheduled]
  @reconcile_batch_size 300
  @history_page_sizes [25, 50, 100]
  @run_statuses ~w(failed running skipped succeeded)
  @task_statuses ~w(disabled failed never paused running skipped succeeded unreviewed)
  @task_sorts [:last_run, :name, :next_due]
  @run_sorts [:name, :source, :started_at, :status]
  @retention_key "schedule.history.keep_days"

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

  @doc "Returns filtered operator-facing schedule facts without worker arguments."
  @spec list_tasks(keyword()) ::
          {:ok, [TaskSummary.t()]} | {:error, :invalid_options | :unavailable}
  def list_tasks(options \\ [])

  def list_tasks(options) when is_list(options) do
    with {:ok, filters} <- validate_task_options(options) do
      definitions = definitions()
      keys = Enum.map(definitions, & &1.key)
      reviews = definition_reviews(keys)
      suppressions = suppression_keys(keys)
      latest_runs = latest_runs(keys)
      now = DateTime.utc_now()

      tasks =
        definitions
        |> Enum.map(&task_summary(&1, reviews, suppressions, latest_runs, now))
        |> filter_tasks(filters)
        |> sort_tasks(filters.sort_by, filters.sort_dir)

      {:ok, tasks}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def list_tasks(_options), do: {:error, :invalid_options}

  @doc "Returns an exact, database-filtered page of redacted run history."
  @spec list_runs(keyword()) ::
          {:ok, RunPage.t()} | {:error, :invalid_options | :unavailable}
  def list_runs(options \\ [])

  def list_runs(options) when is_list(options) do
    with {:ok, filters} <- validate_run_options(options) do
      query = filtered_runs(filters)
      total_entries = Repo.aggregate(query, :count, :id)
      total_pages = ceil_div(total_entries, filters.page_size)

      entries =
        query
        |> order_runs(filters.sort_by, filters.sort_dir)
        |> offset(^((filters.page - 1) * filters.page_size))
        |> limit(^filters.page_size)
        |> Repo.all()
        |> Enum.map(&run_summary/1)

      {:ok,
       %RunPage{
         entries: entries,
         page: filters.page,
         page_size: filters.page_size,
         total_entries: total_entries,
         total_pages: total_pages
       }}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def list_runs(_options), do: {:error, :invalid_options}

  @doc "Reports scheduler, Queue, recorder, and due-work evidence independently."
  @spec diagnostics() :: Diagnostics.t()
  def diagnostics do
    scheduler =
      if Process.whereis(Bilimbi.Base.Schedule.Scheduler),
        do: :available,
        else: :unavailable

    queue_diagnostics = Queue.diagnostics()
    queue = if queue_diagnostics.available?, do: :available, else: :unavailable
    recorder = recorder_availability()

    %Diagnostics{
      scheduler: scheduler,
      queue: queue,
      recorder: recorder,
      due_work: due_work_state()
    }
  end

  @doc "Reviews one immutable definition and records the actor-attributed decision."
  @spec review_definition(Actor.t(), String.t(), boolean()) ::
          :ok | {:error, :audit_unavailable | :not_found | :unavailable}
  def review_definition(%Actor{} = actor, key, enabled)
      when is_binary(key) and is_boolean(enabled) do
    event = if enabled, do: "schedule.task.enabled", else: "schedule.task.disabled"

    operator_action(actor, event, key, %{"enabled" => enabled}, fn ->
      review_definition(key, enabled)
    end)
  end

  def review_definition(%Actor{}, _key, _enabled), do: {:error, :not_found}

  @doc "Pauses a definition and records the actor-attributed action atomically."
  @spec suppress(Actor.t(), String.t()) ::
          :ok | {:error, :audit_unavailable | :not_found | :unavailable}
  def suppress(%Actor{} = actor, key) when is_binary(key) do
    operator_action(actor, "schedule.task.paused", key, %{}, fn -> suppress(key) end)
  end

  def suppress(%Actor{}, _key), do: {:error, :not_found}

  @doc "Resumes a definition and records the actor-attributed action atomically."
  @spec resume(Actor.t(), String.t()) ::
          :ok | {:error, :audit_unavailable | :not_found | :unavailable}
  def resume(%Actor{} = actor, key) when is_binary(key) do
    operator_action(actor, "schedule.task.resumed", key, %{}, fn -> resume(key) end)
  end

  def resume(%Actor{}, _key), do: {:error, :not_found}

  @doc "Queues run-now and records actor attribution in the same database transaction."
  @spec run_now(Actor.t(), String.t()) ::
          {:ok, Queue.JobRef.t()} | {:error, atom()}
  def run_now(%Actor{} = actor, key) when is_binary(key) do
    operator_action(actor, "schedule.run.queued", key, %{}, fn -> run_now(key) end)
  end

  def run_now(%Actor{}, _key), do: {:error, :not_found}

  @doc "Changes global history retention with actor-attributed audit evidence."
  @spec set_history_retention(Actor.t(), integer()) ::
          {:ok, integer()} | {:error, :audit_unavailable | :invalid_retention | :unavailable}
  def set_history_retention(%Actor{} = actor, days) when is_integer(days) and days in 0..3650 do
    operator_action(
      actor,
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

  def set_history_retention(%Actor{}, _days), do: {:error, :invalid_retention}

  @doc "Reviews the current definition fingerprint and explicitly enables or disables it."
  @spec review_definition(String.t(), boolean()) :: :ok | {:error, :not_found | :unavailable}
  def review_definition(key, enabled) when is_binary(key) and is_boolean(enabled) do
    case definition(key) do
      %Definition{} = definition ->
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
          lock_key!(@source, key)

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
          lock_key!(@source, key)

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

  @doc "Queues one operator-requested occurrence; execution is never inline."
  @spec run_now(String.t()) :: {:ok, Queue.JobRef.t()} | {:error, atom()}
  def run_now(key) when is_binary(key) do
    case definition(key) do
      %Definition{} = definition -> enqueue_occurrence(definition, DateTime.utc_now(), :manual)
      nil -> {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
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
  def authorize_execution(metadata, job_id)
      when is_map(metadata) and is_integer(job_id) and job_id > 0 do
    current_definition = definition(metadata["key"])

    case Repo.transaction(fn ->
           lock_key!(metadata["source"], metadata["key"])
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

  defp validate_task_options(options) do
    allowed = [:search, :sort_by, :sort_dir, :status]
    search = Keyword.get(options, :search)
    status = Keyword.get(options, :status)
    sort_by = task_sort(Keyword.get(options, :sort_by, :next_due))
    sort_dir = sort_direction(Keyword.get(options, :sort_dir, :asc))

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         bounded_search?(search) and
         (is_nil(status) or status in @task_statuses) and sort_by in @task_sorts and
         sort_dir in [:asc, :desc] do
      {:ok, %{search: search, status: status, sort_by: sort_by, sort_dir: sort_dir}}
    else
      {:error, :invalid_options}
    end
  end

  defp validate_run_options(options) do
    allowed = [:end_date, :page, :page_size, :search, :sort_by, :sort_dir, :start_date, :status]
    page = Keyword.get(options, :page, 1)
    page_size = Keyword.get(options, :page_size, 25)
    search = Keyword.get(options, :search)
    status = Keyword.get(options, :status)
    start_date = Keyword.get(options, :start_date)
    end_date = Keyword.get(options, :end_date)
    sort_by = run_sort(Keyword.get(options, :sort_by, :started_at))
    sort_dir = sort_direction(Keyword.get(options, :sort_dir, :desc))

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         is_integer(page) and page > 0 and page_size in @history_page_sizes and
         bounded_search?(search) and
         (is_nil(status) or status in @run_statuses) and
         (is_nil(start_date) or match?(%Date{}, start_date)) and
         (is_nil(end_date) or match?(%Date{}, end_date)) and
         valid_date_range?(start_date, end_date) and sort_by in @run_sorts and
         sort_dir in [:asc, :desc] do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         search: search,
         status: status,
         start_date: start_date,
         end_date: end_date,
         sort_by: sort_by,
         sort_dir: sort_dir
       }}
    else
      {:error, :invalid_options}
    end
  end

  defp valid_date_range?(%Date{} = start_date, %Date{} = end_date),
    do: Date.compare(start_date, end_date) != :gt

  defp valid_date_range?(_start_date, _end_date), do: true

  defp bounded_search?(nil), do: true
  defp bounded_search?(search) when is_binary(search), do: byte_size(search) <= 255
  defp bounded_search?(_search), do: false

  defp task_sort(value) when value in @task_sorts, do: value
  defp task_sort("last_run"), do: :last_run
  defp task_sort("name"), do: :name
  defp task_sort("next_due"), do: :next_due
  defp task_sort(_value), do: nil

  defp run_sort(value) when value in @run_sorts, do: value
  defp run_sort("name"), do: :name
  defp run_sort("source"), do: :source
  defp run_sort("started_at"), do: :started_at
  defp run_sort("status"), do: :status
  defp run_sort(_value), do: nil

  defp sort_direction(value) when value in [:asc, :desc], do: value
  defp sort_direction("asc"), do: :asc
  defp sort_direction("desc"), do: :desc
  defp sort_direction(_value), do: nil

  defp definition_reviews([]), do: %{}

  defp definition_reviews(keys) do
    from(review in DefinitionReview,
      where: review.source == @source and review.key in ^keys
    )
    |> Repo.all()
    |> Map.new(&{&1.key, &1})
  end

  defp suppression_keys([]), do: MapSet.new()

  defp suppression_keys(keys) do
    from(suppression in Suppression,
      where: suppression.source == @source and suppression.key in ^keys,
      select: suppression.key
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp latest_runs([]), do: %{}

  defp latest_runs(keys) do
    from(run in Run,
      where: run.source == @source and run.key in ^keys,
      distinct: run.key,
      order_by: [asc: run.key, desc: run.started_at, desc: run.id]
    )
    |> Repo.all()
    |> Map.new(&{{&1.source, &1.key}, &1})
  end

  defp task_summary(definition, reviews, suppressions, latest_runs, now) do
    latest = Map.get(latest_runs, {@source, definition.key})

    %TaskSummary{
      key: definition.key,
      name: definition.name,
      source: @source,
      owner: definition.owner,
      owner_route: definition.owner_route,
      expression: definition.expression,
      timezone: definition.timezone,
      next_due_at: next_due_at(definition, now),
      review_state: review_state(definition, reviews),
      suppressed?: MapSet.member?(suppressions, definition.key),
      overlap: definition.overlap,
      misfire: definition.misfire,
      last_status: last_status(latest),
      last_started_at: latest && latest.started_at,
      last_finished_at: latest && latest.finished_at,
      last_runtime_ms: latest && latest.runtime_ms
    }
  end

  defp next_due_at(definition, now) do
    case Recurrence.next_occurrence(definition, now) do
      {:ok, datetime} ->
        DateTime.shift_zone!(datetime, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)

      {:error, _reason} ->
        nil
    end
  end

  defp review_state(definition, reviews) do
    case Map.get(reviews, definition.key) do
      %DefinitionReview{} = review ->
        cond do
          review.fingerprint != fingerprint(definition) -> :unreviewed
          review.enabled -> :enabled
          true -> :disabled
        end

      _missing_or_changed ->
        :unreviewed
    end
  end

  defp last_status(nil), do: :never

  defp last_status(%Run{status: status}) when status in @run_statuses,
    do: String.to_existing_atom(status)

  defp last_status(%Run{}), do: :unknown

  defp filter_tasks(tasks, filters) do
    search = filters.search && String.downcase(String.trim(filters.search))

    Enum.filter(tasks, fn task ->
      search_matches? =
        is_nil(search) or search == "" or String.contains?(String.downcase(task.name), search)

      status_matches? =
        is_nil(filters.status) or Atom.to_string(task_status(task)) == filters.status

      search_matches? and status_matches?
    end)
  end

  defp task_status(%TaskSummary{suppressed?: true}), do: :paused
  defp task_status(%TaskSummary{review_state: :unreviewed}), do: :unreviewed
  defp task_status(%TaskSummary{review_state: :disabled}), do: :disabled
  defp task_status(%TaskSummary{last_status: status}), do: status

  defp sort_tasks(tasks, sort_by, sort_dir) do
    Enum.sort(tasks, fn left, right ->
      case compare_task(left, right, sort_by, sort_dir) do
        :eq -> left.key <= right.key
        :lt -> true
        :gt -> false
      end
    end)
  end

  defp compare_task(left, right, :name, direction),
    do: compare_values(String.downcase(left.name), String.downcase(right.name), direction)

  defp compare_task(left, right, :next_due, direction),
    do: compare_values(left.next_due_at, right.next_due_at, direction)

  defp compare_task(left, right, :last_run, direction),
    do: compare_values(left.last_started_at, right.last_started_at, direction)

  defp compare_values(nil, nil, _direction), do: :eq
  defp compare_values(nil, _right, _direction), do: :gt
  defp compare_values(_left, nil, _direction), do: :lt

  defp compare_values(%DateTime{} = left, %DateTime{} = right, :asc),
    do: DateTime.compare(left, right)

  defp compare_values(%NaiveDateTime{} = left, %NaiveDateTime{} = right, :asc),
    do: NaiveDateTime.compare(left, right)

  defp compare_values(left, right, :asc) do
    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  defp compare_values(left, right, :desc), do: compare_values(right, left, :asc)

  defp filtered_runs(filters) do
    Run
    |> maybe_search_runs(filters.search)
    |> maybe_filter_run_status(filters.status)
    |> maybe_filter_run_start(filters.start_date)
    |> maybe_filter_run_end(filters.end_date)
  end

  defp maybe_search_runs(query, nil), do: query
  defp maybe_search_runs(query, ""), do: query

  defp maybe_search_runs(query, search) do
    pattern = "%#{escape_like(search)}%"

    from(run in query,
      where: ilike(run.name, ^pattern) or ilike(run.key, ^pattern) or ilike(run.source, ^pattern)
    )
  end

  defp maybe_filter_run_status(query, nil), do: query

  defp maybe_filter_run_status(query, status),
    do: from(run in query, where: run.status == ^status)

  defp maybe_filter_run_start(query, nil), do: query

  defp maybe_filter_run_start(query, start_date) do
    boundary = NaiveDateTime.new!(start_date, ~T[00:00:00])
    from(run in query, where: run.started_at >= ^boundary)
  end

  defp maybe_filter_run_end(query, nil), do: query

  defp maybe_filter_run_end(query, end_date) do
    boundary = end_date |> Date.add(1) |> NaiveDateTime.new!(~T[00:00:00])
    from(run in query, where: run.started_at < ^boundary)
  end

  defp order_runs(query, :started_at, :asc),
    do: from(run in query, order_by: [asc: run.started_at, asc: run.id])

  defp order_runs(query, :started_at, :desc),
    do: from(run in query, order_by: [desc: run.started_at, desc: run.id])

  defp order_runs(query, field, :asc),
    do: from(run in query, order_by: [{:asc, field(run, ^field)}, {:asc, run.id}])

  defp order_runs(query, field, :desc),
    do: from(run in query, order_by: [{:desc, field(run, ^field)}, {:desc, run.id}])

  defp run_summary(%Run{} = run) do
    %RunSummary{
      id: run.id,
      source: run.source,
      key: run.key,
      name: run.name,
      expression: run.expression,
      status: run.status,
      started_at: run.started_at,
      finished_at: run.finished_at,
      exit_code: run.exit_code,
      runtime_ms: run.runtime_ms
    }
  end

  defp ceil_div(0, _page_size), do: 0
  defp ceil_div(total, page_size), do: div(total + page_size - 1, page_size)

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp recorder_availability do
    _ = Repo.one(from(run in Run, select: 1, limit: 1))
    :available
  rescue
    _error -> :unavailable
  catch
    :exit, _reason -> :unavailable
  end

  defp due_work_state do
    definitions = definitions()
    keys = Enum.map(definitions, & &1.key)
    reviews = definition_reviews(keys)
    suppressions = suppression_keys(keys)

    latest = latest_scheduled_occurrences(keys)

    now = DateTime.utc_now()

    if Enum.any?(definitions, &due?(&1, reviews, suppressions, latest, now)) do
      :due
    else
      :none_due
    end
  rescue
    _error -> :unknown
  catch
    :exit, _reason -> :unknown
  end

  defp latest_scheduled_occurrences([]), do: %{}

  defp latest_scheduled_occurrences(keys) do
    from(occurrence in Occurrence,
      where:
        occurrence.source == @source and occurrence.trigger == "scheduled" and
          occurrence.key in ^keys,
      group_by: occurrence.key,
      select: {occurrence.key, max(occurrence.intended_at)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp due?(definition, reviews, suppressions, latest, now) do
    enabled? = review_state(definition, reviews) == :enabled
    paused? = MapSet.member?(suppressions, definition.key)

    with true <- enabled? and not paused?,
         {:ok, intended_at} <- Recurrence.previous_occurrence(definition, now) do
      intended_at =
        DateTime.shift_zone!(intended_at, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)

      case Map.get(latest, definition.key) do
        nil -> true
        claimed_at -> DateTime.before?(claimed_at, intended_at)
      end
    else
      _not_due -> false
    end
  end

  defp operator_action(%Actor{} = actor, event, key, payload, operation) do
    case Repo.transaction(fn ->
           case operation.() do
             {:error, reason} ->
               Repo.rollback(reason)

             result ->
               case record_operator_action(actor, event, key, payload) do
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

  defp record_operator_action(actor, event, key, payload) do
    Audit.record_action(actor.scope, %{
      company_id: actor.company_id,
      actor_type: Actor.principal_type(actor),
      actor_id: actor.id,
      event: event,
      payload: Map.merge(%{"source" => @source, "key" => key}, payload),
      occurred_at: NaiveDateTime.utc_now()
    })
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
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
          "fingerprint" => fingerprint(definition),
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
    availability_after_lock(definition)
  end

  defp availability_after_lock(definition) do
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

  defp authorize_execution_locked(nil, metadata, job_id) do
    cancel_execution_occurrence(metadata, job_id, :not_found)
  end

  defp authorize_execution_locked(definition, metadata, job_id) do
    if fingerprint(definition) != metadata["fingerprint"] do
      cancel_execution_occurrence(metadata, job_id, :changed)
    else
      case availability_after_lock(definition) do
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
    Enum.reduce_while(occurrences, :ok, fn {occurrence_id, job_id}, :ok ->
      case Queue.job_state(job_id) do
        {:ok, state} when state in @active_job_states ->
          {:cont, :ok}

        {:ok, :completed} ->
          reconcile_occurrence(occurrence_id, "succeeded")
          {:cont, :ok}

        {:ok, state} when state in [:cancelled, :discarded] ->
          reconcile_occurrence(occurrence_id, "failed")
          {:cont, :ok}

        {:error, :not_found} ->
          reconcile_occurrence(occurrence_id, "failed")
          {:cont, :ok}

        _unavailable ->
          {:halt, {:error, :unavailable}}
      end
    end)
  end

  defp reconcile_occurrence(occurrence_id, state) do
    Repo.update_all(
      from(item in Occurrence, where: item.id == ^occurrence_id and is_nil(item.finished_at)),
      set: [state: state, finished_at: DateTime.utc_now(), overlap_key: nil]
    )
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

  defp lock_key!(source, key) do
    SQL.query!(Repo.get_dynamic_repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      source <> ":" <> key
    ])

    :ok
  end
end
