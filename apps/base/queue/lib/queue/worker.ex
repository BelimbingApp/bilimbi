defmodule Bilimbi.Base.Queue.Worker do
  @moduledoc """
  Defines the safe boundary implemented by capability-owned queue workers.

  Worker IDs and transport policy are compile-time facts. Callers enqueue only
  JSON-safe arguments and cannot override queue, attempts, or uniqueness.

  A worker whose jobs run as a named system principal declares it here, as a
  compile-time fact of the worker rather than an argument of the job:

      use Bilimbi.Base.Queue.Worker,
        id: "coating/line-import",
        system_principal: "coating.line_import"

  The module that owns the worker must declare that principal under its
  `:system_principals` contribution (ADR 0017). Such a worker is enqueued only
  with `Bilimbi.Base.Queue.enqueue_as_system/4`.
  """

  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals

  @delegated_actor_key "bilimbi_delegated_actor"
  @system_principal_key "bilimbi_system_principal"
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
    system_principal = Keyword.get(opts, :system_principal)

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

    unless is_nil(system_principal) or
             (is_binary(system_principal) and
                system_principal =~ ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/) do
      raise ArgumentError, "queue worker :system_principal must be a declared principal name"
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
        do: %{
          id: unquote(worker_id),
          adapter: unquote(adapter),
          system_principal: unquote(system_principal)
        }

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
  @spec delegated_actor_key() :: String.t()
  def delegated_actor_key, do: @delegated_actor_key

  @doc false
  @spec system_principal_key() :: String.t()
  def system_principal_key, do: @system_principal_key

  @doc false
  def perform(worker, %Oban.Job{} = job) do
    case job_scope(worker, job.meta) do
      {:ok, scope} ->
        execution = %Execution{
          job_id: job.id,
          attempt: job.attempt,
          max_attempts: job.max_attempts,
          queue: job.queue,
          scope: scope
        }

        with_audit_context(scope, fn -> run(worker, job, execution) end)

      # A user who no longer proves out, or a deployment with no verifier,
      # is refused; the cancel reason on the job is the record of it.
      {:error, :actor_refused} ->
        {:cancel, :delegated_actor_refused}

      {:error, :no_actor_verifier} ->
        {:cancel, :no_actor_verifier}

      # A principal nobody declares any more, or a worker that is not the
      # declaring module's code, never runs as that principal.
      {:error, :system_principal_refused} ->
        {:cancel, :system_principal_refused}

      {:error, :system_principal_unavailable} ->
        {:cancel, :system_principal_unavailable}

      # A tampered or expired token, or a tenant gone since enqueue, will not
      # heal on retry. The job never runs as anyone else.
      {:error, _reason} ->
        {:cancel, :delegated_actor_unavailable}
    end
  end

  # A worker that declares a system principal runs only as that principal,
  # from a token `Queue.enqueue_as_system/4` wrote. Every other worker runs as
  # a delegated user or as anonymous system work, never as a principal.
  defp job_scope(worker, meta) do
    case worker.__queue_worker__() do
      %{system_principal: name} when is_binary(name) -> system_principal_scope(worker, name, meta)
      _ordinary -> delegated_scope(meta)
    end
  end

  # `Queue.enqueue_for/3` wrote this token from a scope that already held the
  # user; Base Tenancy verifies it, re-proves the tenant, and asks the
  # installed actor verifier to re-prove the user. This module is the one
  # caller of `Authentication.resume/2`.
  defp delegated_scope(%{@system_principal_key => _token}), do: {:error, :invalid}

  defp delegated_scope(%{@delegated_actor_key => token}) when is_binary(token),
    do: Authentication.resume(token)

  defp delegated_scope(%{@delegated_actor_key => _malformed}), do: {:error, :invalid}
  defp delegated_scope(_meta), do: {:ok, nil}

  # This module is also the one caller of `Authentication.resume_system/2`.
  # The name the scope carries must be the one this worker declared, and the
  # worker must still belong to the module that declares it.
  defp system_principal_scope(worker, name, %{@system_principal_key => token} = meta)
       when is_binary(token) and not is_map_key(meta, @delegated_actor_key) do
    with {:ok, scope} <- resume_system(token),
         %Actor{system_principal: ^name} <- Scope.actor(scope),
         true <- SystemPrincipals.declared_by?(name, worker) do
      {:ok, scope}
    else
      {:error, reason} -> {:error, reason}
      _mismatch -> {:error, :system_principal_refused}
    end
  end

  defp system_principal_scope(_worker, _name, _meta), do: {:error, :system_principal_unavailable}

  defp resume_system(token) do
    case Authentication.resume_system(token) do
      {:ok, scope} -> {:ok, scope}
      {:error, :undeclared_system_principal} -> {:error, :system_principal_refused}
      {:error, _reason} -> {:error, :system_principal_unavailable}
    end
  end

  # Writes a system principal's job makes are captured as that principal
  # (ADR 0013, ADR 0017), not as the guest default.
  defp with_audit_context(%Scope{} = scope, fun) do
    case Scope.actor(scope) do
      %Actor{type: :system, system_principal: name, company_id: company_id}
      when is_binary(name) ->
        AuditContext.put(%AuditContext{
          actor_type: "system",
          actor_id: 0,
          system_principal: name,
          company_id: company_id,
          tenant_id: Scope.tenant_id(scope)
        })

        try do
          fun.()
        after
          AuditContext.put(nil)
        end

      %Actor{} ->
        fun.()
    end
  end

  defp with_audit_context(nil, fun), do: fun.()

  defp run(worker, job, execution) do
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
