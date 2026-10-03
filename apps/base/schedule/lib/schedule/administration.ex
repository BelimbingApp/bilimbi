defmodule Bilimbi.Base.Schedule.Administration do
  @moduledoc false

  # Operator read model for the schedule board. `Schedule.list_tasks/1` and
  # `Schedule.list_runs/1` delegate here, the same split as
  # `Bilimbi.Base.Authz.Administration`. Paging and filtering stay in this
  # module; the facade keeps operator actions and the occurrence engine.

  import Ecto.Query

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Schedule.Definition
  alias Bilimbi.Base.Schedule.DefinitionReview
  alias Bilimbi.Base.Schedule.Occurrence
  alias Bilimbi.Base.Schedule.Recurrence
  alias Bilimbi.Base.Schedule.Run
  alias Bilimbi.Base.Schedule.RunPage
  alias Bilimbi.Base.Schedule.RunSummary
  alias Bilimbi.Base.Schedule.Suppression
  alias Bilimbi.Base.Schedule.TaskSummary

  # Same occurrence source the engine writes. The read model filters on it.
  @source "scheduler"
  @history_page_sizes [25, 50, 100]
  @run_statuses ~w(failed running skipped succeeded)
  @task_statuses ~w(disabled failed never paused running skipped succeeded unreviewed)
  @task_sorts [:last_run, :name, :next_due]
  @run_sorts [:name, :source, :started_at, :status]
  @utc "UTC"
  @tz_db TimeZoneInfo.TimeZoneDatabase

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

  @doc false
  def latest_scheduled_occurrence(%Definition{} = definition) do
    latest_scheduled_occurrences([definition.key]) |> Map.get(definition.key)
  rescue
    _error -> nil
  catch
    :exit, _reason -> nil
  end

  @doc false
  def latest_scheduled_occurrences([]), do: %{}

  def latest_scheduled_occurrences(keys) when is_list(keys) do
    from(item in Occurrence,
      where: item.source == @source and item.trigger == "scheduled" and item.key in ^keys,
      group_by: item.key,
      select: {item.key, max(item.intended_at)}
    )
    |> Repo.all()
    |> Map.new()
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
    allowed = [
      :end_date,
      :page,
      :page_size,
      :search,
      :sort_by,
      :sort_dir,
      :start_date,
      :status,
      :timezone
    ]

    page = Keyword.get(options, :page, 1)
    page_size = Keyword.get(options, :page_size, 25)
    search = Keyword.get(options, :search)
    status = Keyword.get(options, :status)
    start_date = Keyword.get(options, :start_date)
    end_date = Keyword.get(options, :end_date)
    timezone = Keyword.get(options, :timezone, @utc)
    sort_by = run_sort(Keyword.get(options, :sort_by, :started_at))
    sort_dir = sort_direction(Keyword.get(options, :sort_dir, :desc))

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) and
         is_integer(page) and page > 0 and page_size in @history_page_sizes and
         bounded_search?(search) and
         (is_nil(status) or status in @run_statuses) and
         (is_nil(start_date) or match?(%Date{}, start_date)) and
         (is_nil(end_date) or match?(%Date{}, end_date)) and
         valid_date_range?(start_date, end_date) and valid_timezone?(timezone) and
         sort_by in @run_sorts and sort_dir in [:asc, :desc] do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         search: search,
         status: status,
         start_date: start_date,
         end_date: end_date,
         timezone: timezone,
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

  # The filter zone is a caller-supplied string, so it is proved against the
  # real database before it can bound a query; an unknown name is refused
  # rather than silently read as UTC.
  defp valid_timezone?(timezone) when is_binary(timezone) do
    match?({:ok, _now}, DateTime.now(timezone, @tz_db))
  end

  defp valid_timezone?(_timezone), do: false

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
      fingerprint: fingerprint(definition),
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
    |> maybe_filter_run_start(filters.start_date, filters.timezone)
    |> maybe_filter_run_end(filters.end_date, filters.timezone)
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

  # A date filter bounds calendar days of the zone the caller displays
  # `started_at` in, so the day a row is shown on and the day a filter selects
  # are the same day. Both boundaries are that zone's midnight expressed as the
  # stored UTC instant: the start day begins at its own midnight and the end
  # day ends where the next day begins.
  defp maybe_filter_run_start(query, nil, _timezone), do: query

  defp maybe_filter_run_start(query, start_date, timezone) do
    boundary = day_start(start_date, timezone)
    from(run in query, where: run.started_at >= ^boundary)
  end

  defp maybe_filter_run_end(query, nil, _timezone), do: query

  defp maybe_filter_run_end(query, end_date, timezone) do
    boundary = end_date |> Date.add(1) |> day_start(timezone)
    from(run in query, where: run.started_at < ^boundary)
  end

  defp day_start(date, timezone) do
    case DateTime.new(date, ~T[00:00:00], timezone, @tz_db) do
      {:ok, midnight} ->
        midnight

      # Clocks jumped forward over midnight: the day begins the moment they
      # resume, so nothing that happened that night is dropped.
      {:gap, _just_before, just_after} ->
        just_after

      # Clocks fell back over midnight: the day begins at the first of its two
      # midnights, so the repeated hour still belongs to the day it displays in.
      {:ambiguous, first, _second} ->
        first
    end
    |> DateTime.shift_zone!(@utc, @tz_db)
    |> DateTime.to_naive()
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

  @doc false
  def due_work_state do
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
end
