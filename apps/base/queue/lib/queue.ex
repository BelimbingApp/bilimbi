defmodule Bilimbi.Base.Queue do
  @moduledoc """
  Durable transport and execution policy for capability-owned background work.

  The public boundary exposes stable references and redacted summaries. Oban
  schemas, changesets, job arguments, errors, and stack traces never escape.
  """

  import Ecto.Query

  alias Bilimbi.Base.Queue.Arguments
  alias Bilimbi.Base.Queue.Diagnostics
  alias Bilimbi.Base.Queue.JobPage
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Queue.JobSummary
  alias Bilimbi.Base.Repo
  alias Ecto.Multi
  alias Oban.Job

  @application :bilimbi_base_queue
  @default_page_size 25
  @page_sizes [25, 50, 100]
  @queues ["default"]
  @states ~w(available scheduled executing retryable completed cancelled discarded)

  @doc false
  @spec oban_config() :: keyword()
  def oban_config do
    defaults = [
      name: Bilimbi.Base.Queue.Oban,
      repo: Repo,
      queues: [default: 10],
      plugins: [{Oban.Plugins.Pruner, max_age: 604_800}],
      shutdown_grace_period: 15_000
    ]

    overrides =
      for key <- [:name, :repo, :queues, :plugins, :shutdown_grace_period, :testing],
          value = Application.get_env(@application, key),
          value != nil,
          do: {key, value}

    Keyword.merge(defaults, overrides)
  end

  @doc "Enqueues validated plain-data arguments for a Queue worker."
  @spec enqueue(module(), term()) :: {:ok, JobRef.t()} | {:error, atom()}
  def enqueue(worker, args) do
    with {:ok, worker_info} <- worker_info(worker),
         {:ok, safe_args} <- Arguments.validate(args) do
      insert_job(worker_info, safe_args)
    end
  end

  @doc "Adds an atomic queue insertion to an existing Ecto.Multi."
  @spec enqueue(Multi.t(), term(), module(), map() | (map() -> map())) :: Multi.t()
  def enqueue(%Multi{} = multi, operation, worker, args_or_fun)
      when is_map(args_or_fun) or is_function(args_or_fun, 1) do
    Multi.run(multi, operation, fn _repo, changes ->
      args = if is_function(args_or_fun, 1), do: args_or_fun.(changes), else: args_or_fun
      enqueue(worker, args)
    end)
  end

  @doc "Cancels a positive job ID without returning transport state."
  @spec cancel(term()) :: :ok | {:error, :not_found | :invalid_job_id | :unavailable}
  def cancel(job_id) when is_integer(job_id) and job_id > 0 do
    if job_exists?(job_id) do
      Oban.cancel_job(oban_name(), job_id)
    else
      {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def cancel(_job_id), do: {:error, :invalid_job_id}

  @doc "Retries a positive inactive job ID without returning transport state."
  @spec retry(term()) :: :ok | {:error, :not_found | :invalid_job_id | :unavailable}
  def retry(job_id) when is_integer(job_id) and job_id > 0 do
    if job_exists?(job_id) do
      Oban.retry_job(oban_name(), job_id)
    else
      {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def retry(_job_id), do: {:error, :invalid_job_id}

  @doc "Returns a bounded page of redacted operational facts."
  @spec list_jobs(keyword()) :: {:ok, JobPage.t()} | {:error, :invalid_options | :unavailable}
  def list_jobs(options \\ [])

  def list_jobs(options) when is_list(options) do
    with {:ok, filters} <- validate_list_options(options) do
      query = filtered_jobs(filters)
      total = Repo.aggregate(query, :count, :id)

      entries =
        query
        |> order_by([job], desc: job.inserted_at, desc: job.id)
        |> limit(^filters.page_size)
        |> offset(^((filters.page - 1) * filters.page_size))
        |> select([job], %{
          id: job.id,
          worker: job.worker,
          worker_id: fragment("?->>?", job.meta, "bilimbi_worker_id"),
          queue: job.queue,
          state: job.state,
          attempt: job.attempt,
          max_attempts: job.max_attempts,
          inserted_at: job.inserted_at,
          scheduled_at: job.scheduled_at,
          completed_at: job.completed_at
        })
        |> Repo.all()
        |> Enum.map(&to_job_summary/1)

      {:ok,
       %JobPage{
         entries: entries,
         page: filters.page,
         page_size: filters.page_size,
         total: total
       }}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def list_jobs(_options), do: {:error, :invalid_options}

  @doc "Returns fixed, redacted backlog and recovery aggregates."
  @spec diagnostics() :: Diagnostics.t()
  def diagnostics do
    if Oban.whereis(oban_name()) do
      counts =
        from(job in Job, group_by: job.state, select: {job.state, count(job.id)})
        |> Repo.all()
        |> Map.new()

      %Diagnostics{
        available?: true,
        backlog: count_states(counts, ~w(available scheduled)),
        executing: Map.get(counts, "executing", 0),
        retryable: Map.get(counts, "retryable", 0),
        discarded: Map.get(counts, "discarded", 0)
      }
    else
      unavailable_diagnostics()
    end
  rescue
    _error -> unavailable_diagnostics()
  catch
    :exit, _reason -> unavailable_diagnostics()
  end

  @doc false
  def health_status do
    case diagnostics() do
      %Diagnostics{available?: true, backlog: backlog, retryable: retryable, discarded: discarded} ->
        "Available (#{backlog} pending, #{retryable} retryable, #{discarded} discarded)"

      %Diagnostics{} ->
        :unavailable
    end
  end

  defp insert_job(worker_info, args) do
    changeset =
      worker_info.adapter.new(args,
        meta: %{"bilimbi_worker_id" => worker_info.id}
      )

    case Oban.insert(oban_name(), changeset) do
      {:ok, %Job{} = job} -> {:ok, to_job_ref(job, worker_info.id)}
      {:error, _reason} -> {:error, :insertion_failed}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp worker_info(worker) when is_atom(worker) do
    if Code.ensure_loaded?(worker) and function_exported?(worker, :__queue_worker__, 0) do
      case worker.__queue_worker__() do
        %{id: id, adapter: adapter} when is_binary(id) and is_atom(adapter) ->
          {:ok, %{id: id, adapter: adapter}}

        _invalid ->
          {:error, :unsupported_worker}
      end
    else
      {:error, :unsupported_worker}
    end
  end

  defp worker_info(_worker), do: {:error, :unsupported_worker}

  defp validate_list_options(options) do
    allowed_keys = [:page, :page_size, :queue, :state]

    page = Keyword.get(options, :page, 1)
    page_size = Keyword.get(options, :page_size, @default_page_size)
    queue = Keyword.get(options, :queue)
    state = Keyword.get(options, :state)

    if Keyword.keyword?(options) and
         Enum.all?(Keyword.keys(options), &(&1 in allowed_keys)) and
         is_integer(page) and page > 0 and page_size in @page_sizes and
         (is_nil(queue) or queue in @queues) and (is_nil(state) or state in @states) do
      {:ok, %{page: page, page_size: page_size, queue: queue, state: state}}
    else
      {:error, :invalid_options}
    end
  end

  defp filtered_jobs(filters) do
    Job
    |> maybe_filter(:queue, filters.queue)
    |> maybe_filter(:state, filters.state)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :queue, queue), do: where(query, [job], job.queue == ^queue)
  defp maybe_filter(query, :state, state), do: where(query, [job], job.state == ^state)

  defp to_job_ref(job, worker_id) do
    %JobRef{
      id: job.id,
      worker_id: worker_id,
      state: state_atom(job.state),
      conflict?: job.conflict?
    }
  end

  defp to_job_summary(row) do
    %JobSummary{
      id: row.id,
      worker_id: row.worker_id || "unavailable",
      queue: row.queue,
      state: state_atom(row.state),
      attempt: row.attempt,
      max_attempts: row.max_attempts,
      available?: adapter_available?(row.worker, row.worker_id),
      inserted_at: row.inserted_at,
      scheduled_at: row.scheduled_at,
      completed_at: row.completed_at
    }
  end

  defp adapter_available?(worker_name, worker_id) do
    with module when is_atom(module) <- Module.safe_concat([worker_name]),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :__queue_worker_id__, 0) do
      module.__queue_worker_id__() == worker_id
    else
      _other -> false
    end
  rescue
    ArgumentError -> false
  end

  defp state_atom("available"), do: :available
  defp state_atom("scheduled"), do: :scheduled
  defp state_atom("executing"), do: :executing
  defp state_atom("retryable"), do: :retryable
  defp state_atom("completed"), do: :completed
  defp state_atom("cancelled"), do: :cancelled
  defp state_atom("discarded"), do: :discarded
  defp state_atom(_unknown), do: :unknown

  defp job_exists?(job_id), do: Repo.exists?(from job in Job, where: job.id == ^job_id)
  defp oban_name, do: Keyword.fetch!(oban_config(), :name)

  defp count_states(counts, states) do
    Enum.reduce(states, 0, &(&2 + Map.get(counts, &1, 0)))
  end

  defp unavailable_diagnostics do
    %Diagnostics{available?: false, backlog: 0, executing: 0, retryable: 0, discarded: 0}
  end
end
