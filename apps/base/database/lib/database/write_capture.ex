defmodule Bilimbi.Base.Database.WriteCapture do
  @moduledoc """
  The repo-level write-capture seam (ADR 0013, #630).

  `Bilimbi.Base.Repo` calls `dispatch/3` after every **successful** struct
  write. The capture module comes from workspace configuration
  (`:bilimbi_base_database, :write_capture`) — Base Database defines the
  seam and gains no dependency on whoever implements it, the same wiring
  shape as Core User's `:pubsub_server`.

  Capture must never fail the business write: a raise inside the capture
  module is rescued, logged without row values, and counted on the
  `[:bilimbi, :base, :audit, :capture_failure]` telemetry event.

  `without_capture/1` is the port of Belimbing's
  `MutationListener::withoutAuditing` — a process flag restored by
  `after`, for seeds, schema lifecycle tasks, and reconciliation writes.
  """

  require Logger

  @capture_disabled_key __MODULE__

  @typedoc "The struct write that succeeded."
  @type action :: :insert | :update | :delete

  @doc """
  Invoked after a successful struct write.

  `source` is what the caller handed the repo — an `Ecto.Changeset` for
  changeset writes (carrying both originals and changes) or a bare struct —
  and `result` is the written struct the repo returned.
  """
  @callback after_write(action(), Ecto.Changeset.t() | Ecto.Schema.t(), Ecto.Schema.t()) :: :ok

  @doc "Runs `fun` with write capture disabled in this process."
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
      # Redacted: the schema module is diagnostic, row values never are.
      :telemetry.execute([:bilimbi, :base, :audit, :capture_failure], %{count: 1}, %{
        action: action,
        schema: schema_of(source)
      })

      Logger.error(
        "audit write capture failed for #{inspect(schema_of(source))} #{action}: " <>
          Exception.format(:error, error, [])
      )

      :ok
  end

  defp schema_of(%Ecto.Changeset{data: %schema{}}), do: schema
  defp schema_of(%schema{}), do: schema
  defp schema_of(_other), do: :unknown
end
