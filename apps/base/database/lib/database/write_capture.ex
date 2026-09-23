defmodule Bilimbi.Base.Database.WriteCapture do
  @moduledoc """
  The repo-level write-capture seam (ADR 0013, #630).

  `Bilimbi.Base.Repo` calls `dispatch/3` after every **successful** struct
  write and `dispatch_bulk/2` after every successful query-based bulk write
  (`insert_all`, `update_all`, `delete_all`), whose affected rows
  `Bilimbi.Base.Database.BulkCapture` gathers. The capture module comes from workspace configuration
  (`:bilimbi_base_database, :write_capture`) — Base Database defines the
  seam and gains no dependency on whoever implements it, the same wiring
  shape as Core User's `:pubsub_server`.

  Capture must never fail the business write: a raise inside the capture
  module is rescued, logged without row values, and counted on the
  `[:bilimbi, :base, :audit, :capture_failure]` telemetry event.

  `without_capture/1` is the port of Belimbing's
  `MutationListener::withoutAuditing` — a process flag restored by
  `after`, for seeds, schema lifecycle tasks, and reconciliation writes.
  It covers bulk writes too, and suppresses their pre-reads as well as
  their audit rows.
  """

  require Logger

  @capture_disabled_key __MODULE__

  @typedoc "The write that succeeded."
  @type action :: :insert | :update | :delete

  @typedoc """
  One row a bulk write affected: what happened to it, the row as it was,
  and the row as it now is.

  An insert carries no prior row and a delete no resulting one. An upsert
  that replaced an existing row carries both and arrives as `:update`.
  """
  @type change :: {action(), Ecto.Schema.t() | nil, Ecto.Schema.t() | nil}

  @doc """
  Invoked after a successful struct write.

  `source` is what the caller handed the repo — an `Ecto.Changeset` for
  changeset writes (carrying both originals and changes) or a bare struct —
  and `result` is the written struct the repo returned.
  """
  @callback after_write(action(), Ecto.Changeset.t() | Ecto.Schema.t(), Ecto.Schema.t()) :: :ok

  @doc """
  Invoked after a successful query-based bulk write, with one `t:change/0`
  per row the statement affected.

  A bulk write reaches the capture module as rows, not as a changeset:
  `insert_all` and `delete_all` read them from `RETURNING`, and
  `update_all` pairs a pre-read against `RETURNING`.
  """
  @callback after_bulk_write(module(), [change()]) :: :ok

  @doc """
  Whether writes to `schema` are captured at all.

  The repo asks **before** a bulk write, so a schema the capture module
  excludes pays none of the pre-read or `RETURNING` cost that gathering
  its rows would otherwise add.
  """
  @callback capture_schema?(module()) :: boolean()

  @doc """
  Runs `fun` with write capture disabled in this process.

  Call this only with a written reason for that table, at a machine-only
  site whose other writes stay captured. A missing actor is not a reason:
  the audit policy records that write as guest. Schema-wide silence is
  `:bilimbi_base_audit, :exclude_schemas`, not this function.
  """
  @spec without_capture((-> result)) :: result when result: var
  def without_capture(fun) when is_function(fun, 0) do
    previous = Process.put(@capture_disabled_key, true)

    try do
      fun.()
    after
      case previous do
        nil -> Process.delete(@capture_disabled_key)
        value -> Process.put(@capture_disabled_key, value)
      end
    end
  end

  @doc "Whether capture is disabled in this process."
  @spec disabled?() :: boolean()
  def disabled?, do: Process.get(@capture_disabled_key, false) == true

  @doc """
  Whether a bulk write to `schema` should be gathered and captured.

  False for anything that is not an Ecto schema module — a raw table name
  or a schemaless query carries no field metadata to record — and false
  whenever capture is unconfigured, disabled in this process, or the
  capture module excludes the schema.
  """
  @spec bulk_captured?(term()) :: boolean()
  def bulk_captured?(schema) when is_atom(schema) and not is_nil(schema) do
    capture = Application.get_env(:bilimbi_base_database, :write_capture)

    loaded?(capture) and not disabled?() and
      loaded?(schema) and function_exported?(schema, :__schema__, 1) and
      capture.capture_schema?(schema)
  end

  def bulk_captured?(_other), do: false

  # A configured capture module that is not loaded cannot answer, and the
  # repo asks this before every bulk write to decide whether to pay for
  # gathering rows. Reporting it here would report it once per statement;
  # `dispatch/3` still reports it on the next struct write, which is where
  # a genuine misconfiguration surfaces.
  defp loaded?(nil), do: false
  defp loaded?(module) when is_atom(module), do: Code.ensure_loaded?(module)

  @doc false
  @spec dispatch_bulk(module(), [change()]) :: :ok
  def dispatch_bulk(_schema, []), do: :ok

  def dispatch_bulk(schema, changes) do
    capture = Application.get_env(:bilimbi_base_database, :write_capture)

    if capture && not disabled?() do
      without_capture(fn -> capture.after_bulk_write(schema, changes) end)
    end

    :ok
  rescue
    error ->
      capture_failed(:bulk, schema, error, __STACKTRACE__)
  end

  @doc false
  @spec dispatch(action(), Ecto.Changeset.t() | Ecto.Schema.t(), term()) :: :ok
  def dispatch(action, source, result) do
    capture = Application.get_env(:bilimbi_base_database, :write_capture)

    if capture && not disabled?() do
      # Capture must not observe its own writes; the flag also guards
      # against a capture module that forgets its own recursion guard.
      without_capture(fn -> capture.after_write(action, source, result) end)
    end

    :ok
  rescue
    error ->
      capture_failed(action, schema_of(source), error, __STACKTRACE__)
  end

  @doc false
  @spec capture_failed(atom(), module() | atom(), Exception.t(), Exception.stacktrace()) :: :ok
  def capture_failed(action, schema, error, stacktrace) do
    # Redacted: the schema module is diagnostic, row values never are.
    :telemetry.execute([:bilimbi, :base, :audit, :capture_failure], %{count: 1}, %{
      action: action,
      schema: schema
    })

    Logger.error(
      "audit write capture failed for #{inspect(schema)} #{action}: " <>
        Exception.format(:error, error, stacktrace)
    )

    :ok
  end

  defp schema_of(%Ecto.Changeset{data: %schema{}}), do: schema
  defp schema_of(%schema{}), do: schema
  defp schema_of(_other), do: :unknown
end
