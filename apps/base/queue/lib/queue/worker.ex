defmodule Bilimbi.Base.Queue.Worker do
  @moduledoc """
  Defines the safe boundary implemented by capability-owned queue workers.

  Worker IDs and transport policy are compile-time facts. Callers enqueue only
  JSON-safe arguments and cannot override queue, attempts, or uniqueness.
  """

  alias Bilimbi.Base.Queue.Execution

  @failure_code_pattern ~r/^[a-z][a-z0-9_]{0,63}$/

  @type failure_code :: atom()
  @type result :: :ok | {:retry, failure_code()} | {:cancel, failure_code()}

  @callback validate_args(map()) :: {:ok, map()} | {:error, failure_code()}
  @callback handle_job(map(), Execution.t()) :: result()

  defmacro __using__(opts) do
    caller = __CALLER__.module
    worker_id = Keyword.fetch!(opts, :id)
    queue = Keyword.get(opts, :queue, :default)
    max_attempts = Keyword.get(opts, :max_attempts, 20)
    unique_period = Keyword.get(opts, :unique_period)

    unless is_binary(worker_id) and worker_id =~ ~r/^[a-z0-9][a-z0-9_\/-]{0,127}$/ do
      raise ArgumentError, "queue worker :id must be a stable lowercase identifier"
    end

    unless queue == :default and is_integer(max_attempts) and max_attempts > 0 do
      raise ArgumentError, "queue worker requires the :default queue and positive max_attempts"
    end

    if unique_period != nil and
         not (is_integer(unique_period) and unique_period > 0) do
      raise ArgumentError, "queue worker unique_period must be a positive integer"
    end

    adapter = Module.concat(caller, ObanAdapter)

    oban_opts =
      [queue: queue, max_attempts: max_attempts]
      |> then(fn options ->
        if unique_period,
          do: Keyword.put(options, :unique, period: unique_period),
          else: options
      end)

    quote do
      @behaviour Bilimbi.Base.Queue.Worker

      @doc false
      def __queue_worker__,
        do: %{id: unquote(worker_id), adapter: unquote(adapter)}

      defmodule unquote(adapter) do
        @moduledoc false

        use Oban.Worker, unquote(oban_opts)

        @doc false
        def __queue_worker_id__, do: unquote(worker_id)

        @impl Oban.Worker
        def perform(%Oban.Job{} = job) do
          Bilimbi.Base.Queue.Worker.perform(unquote(caller), job)
        end
      end
    end
  end

  @doc false
  @spec normalize_args(module(), map()) :: {:ok, map()} | {:error, :invalid_args}
  def normalize_args(worker, args) do
    case worker.validate_args(args) do
      {:ok, normalized_args} when is_map(normalized_args) -> {:ok, normalized_args}
      _invalid -> {:error, :invalid_args}
    end
  rescue
    _error -> {:error, :invalid_args}
  catch
    _kind, _reason -> {:error, :invalid_args}
  end

  @doc false
  def perform(worker, %Oban.Job{} = job) do
    execution = %Execution{
      job_id: job.id,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      queue: job.queue
    }

    case worker.validate_args(job.args) do
      {:ok, normalized_args} ->
        case worker.handle_job(normalized_args, execution) do
          :ok -> :ok
          {:retry, code} -> retry_result(code)
          {:cancel, code} -> cancel_result(code)
          _invalid -> {:error, :invalid_worker_result}
        end

      {:error, code} ->
        cancel_args_result(code)

      _invalid ->
        {:cancel, :invalid_worker_args}
    end
  end

  defp retry_result(code) do
    if valid_failure_code?(code), do: {:error, code}, else: {:error, :invalid_worker_result}
  end

  defp cancel_result(code) do
    if valid_failure_code?(code), do: {:cancel, code}, else: {:error, :invalid_worker_result}
  end

  defp cancel_args_result(code) do
    if valid_failure_code?(code), do: {:cancel, code}, else: {:cancel, :invalid_worker_args}
  end

  defp valid_failure_code?(code) when is_atom(code) do
    Regex.match?(@failure_code_pattern, Atom.to_string(code))
  end

  defp valid_failure_code?(_code), do: false
end
