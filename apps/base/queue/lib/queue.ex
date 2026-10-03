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
  alias Bilimbi.Base.Queue.Worker
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals
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
      prefix: "public",
      queues: [default: 10],
      plugins: [{Oban.Plugins.Pruner, max_age: 604_800}],
      shutdown_grace_period: 15_000
    ]

    overrides =
      for key <- [
            :name,
            :repo,
            :prefix,
            :queues,
            :plugins,
            :shutdown_grace_period,
            :testing,
            :get_dynamic_repo
          ],
          value = Application.get_env(@application, key),
          value != nil,
          do: {key, value}

    Keyword.merge(defaults, overrides)
  end

  @doc """
  Enqueues validated plain-data arguments for a Queue worker.

  A worker that declares a system principal is refused with
  `:system_principal_worker`: it runs only through `enqueue_as_system/4`.
  """
  @spec enqueue(module(), term()) :: {:ok, JobRef.t()} | {:error, atom()}
  def enqueue(worker, args), do: enqueue_job(worker, args, %{})

  @doc """
  Enqueues work that acts for the scope's signed-in user.

  When the job runs, its `Bilimbi.Base.Queue.Execution` carries that user's
  scope in `:scope`, so the worker passes an actor to module APIs exactly as a
  signed-in request does. The actor travels as a token Base Tenancy signed
  from this scope, in job metadata a caller cannot write — never in the
  arguments, which any caller shapes. A system scope has nobody to act for:
  use `enqueue/2`.

  A worker that declares `unique_period` is refused with `:unique_worker`.
  Oban compares arguments, not metadata, so a duplicate would be absorbed by
  a job that carries another user, or none, and run as them.
  """
  @spec enqueue_for(Scope.t(), module(), term()) :: {:ok, JobRef.t()} | {:error, atom()}
  def enqueue_for(%Scope{} = scope, worker, args) do
    with {:ok, token} <- Authentication.delegate(scope) do
      enqueue_job(worker, args, %{Worker.delegated_actor_key() => token})
    end
  end

  @doc """
  Enqueues work that runs as the worker's named system principal.

  Routine system work, such as a scheduled import, is not tied to whoever
  signed in to start it. The worker declares its principal
  (`use Bilimbi.Base.Queue.Worker, system_principal: "coating.line_import"`), and
  the module that owns the worker must declare that name under its
  `:system_principals` contribution (ADR 0017). When the job runs,
  `execution.scope` is the scope's tenant with that principal as its actor,
  working in `company_id`, and captured writes are attributed to it. Only the
  tenant is taken from `scope`; its actor is not carried into the job.

  Refusals: `:not_system_principal_worker` for a worker that declares none,
  `:undeclared_system_principal` when no installed module declares its name
  or the worker is not that module's code, `:invalid_company` for a company
  ID that is not a positive integer, and `:unique_worker` for a worker that
  declares `unique_period`. The principal holds only the capabilities an
  administrator granted it in that company, decided by Base Authz when the
  job runs.
  """
  @spec enqueue_as_system(Scope.t(), pos_integer(), module(), term()) ::
          {:ok, JobRef.t()} | {:error, atom()}
  def enqueue_as_system(%Scope{} = scope, company_id, worker, args) do
    with {:ok, %{system_principal: name}} when is_binary(name) <- worker_info(worker),
         true <- SystemPrincipals.declared_by?(name, worker),
         {:ok, token} <- Authentication.delegate_system(scope, name, company_id) do
      enqueue_job(worker, args, %{Worker.system_principal_key() => token})
    else
      {:ok, %{}} -> {:error, :not_system_principal_worker}
      false -> {:error, :undeclared_system_principal}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_job(worker, args, meta) do
    with {:ok, worker_info} <- worker_info(worker),
         :ok <- ensure_principal_matches(worker_info, meta),
         :ok <- ensure_delegable(worker_info, meta),
         {:ok, safe_args} <- Arguments.validate(args),
         {:ok, normalized_args} <- Worker.normalize_args(worker, safe_args),
         {:ok, normalized_args} <- Arguments.validate(normalized_args) do
      insert_job(worker_info, normalized_args, meta)
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

  @doc "Returns one job's bounded transport state for capability-owned reconciliation."
  @spec job_state(term()) ::
          {:ok, atom()} | {:error, :not_found | :invalid_job_id | :unavailable}
  def job_state(job_id) when is_integer(job_id) and job_id > 0 do
    case Repo.one(from(job in jobs_query(), where: job.id == ^job_id, select: job.state)) do
      nil -> {:error, :not_found}
      state -> {:ok, state_atom(state)}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def job_state(_job_id), do: {:error, :invalid_job_id}

  @doc "Returns the bounded transport states for a set of positive job IDs."
  @spec job_states([term()]) ::
          {:ok, %{optional(pos_integer()) => atom()}} | {:error, :invalid_job_id | :unavailable}
  def job_states(job_ids) when is_list(job_ids) do
    cond do
      not Enum.all?(job_ids, &(is_integer(&1) and &1 > 0)) ->
        {:error, :invalid_job_id}

      job_ids == [] ->
        {:ok, %{}}

      true ->
        states =
          from(job in jobs_query(), where: job.id in ^job_ids, select: {job.id, job.state})
          |> Repo.all()
          |> Map.new(fn {id, state} -> {id, state_atom(state)} end)

        {:ok, states}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def job_states(_job_ids), do: {:error, :invalid_job_id}

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
        jobs_query()
        |> group_by([job], job.state)
        |> select([job], {job.state, count(job.id)})
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
  @spec health_status() :: String.t() | :unavailable
  def health_status do
    case diagnostics() do
      %Diagnostics{available?: true, backlog: backlog, retryable: retryable, discarded: discarded} ->
        "Available (#{backlog} pending, #{retryable} retryable, #{discarded} discarded)"

      %Diagnostics{} ->
        :unavailable
    end
  end

  defp insert_job(worker_info, args, meta) do
    changeset =
      worker_info.adapter.new(args,
        meta: Map.put(meta, "bilimbi_worker_id", worker_info.id)
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
        %{id: id, adapter: adapter} = info when is_binary(id) and is_atom(adapter) ->
          {:ok, %{id: id, adapter: adapter, system_principal: Map.get(info, :system_principal)}}

        _invalid ->
          {:error, :unsupported_worker}
      end
    else
      {:error, :unsupported_worker}
    end
  end

  defp worker_info(_worker), do: {:error, :unsupported_worker}

  # A principal's worker runs only as that principal, so it is never enqueued
  # as ordinary or user work.
  defp ensure_principal_matches(%{system_principal: nil}, _meta), do: :ok

  defp ensure_principal_matches(_worker_info, meta) do
    if Map.has_key?(meta, Worker.system_principal_key()),
      do: :ok,
      else: {:error, :system_principal_worker}
  end

  # Oban's uniqueness compares arguments, not metadata, so a duplicate would
  # be absorbed by a job carrying another actor, tenant, or company.
  defp ensure_delegable(worker_info, meta) do
    if (Map.has_key?(meta, Worker.delegated_actor_key()) or
          Map.has_key?(meta, Worker.system_principal_key())) and
         worker_info.adapter.__opts__()[:unique] != nil,
       do: {:error, :unique_worker},
       else: :ok
  end

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
    jobs_query()
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

  defp job_exists?(job_id), do: Repo.exists?(where(jobs_query(), [job], job.id == ^job_id))
  defp jobs_query, do: Ecto.Query.put_query_prefix(Job, oban_prefix())
  defp oban_name, do: Keyword.fetch!(oban_config(), :name)
  defp oban_prefix, do: Keyword.fetch!(oban_config(), :prefix)

  defp count_states(counts, states) do
    Enum.reduce(states, 0, &(&2 + Map.get(counts, &1, 0)))
  end

  defp unavailable_diagnostics do
    %Diagnostics{available?: false, backlog: 0, executing: 0, retryable: 0, discarded: 0}
  end
end
