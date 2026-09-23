defmodule Bilimbi.Base.Database.ConsoleCapture do
  @moduledoc """
  The console-command capture seam.

  `Bilimbi.Base.Database.QueryExecutor` calls `dispatch/3` after **every**
  command handed to `Bilimbi.Base.Database.execute_readonly/3`, whatever
  its outcome: succeeded, refused by a guard, or failed at the database.
  The seam sits below the console's screens rather than in them, so no
  event handler, page, or future caller can run console SQL without the
  command being recorded — the same wiring shape as `WriteCapture`.

  The capture module comes from workspace configuration
  (`:bilimbi_base_database, :console_capture`); Base Database defines the
  seam and gains no dependency on whoever implements it.

  A capture receives the command text and its outcome, never the result
  rows: rows can be large and can carry the data the record must not copy.

  Capture must never change a command's answer: a raise inside the capture
  module is rescued, logged without the command text, and counted on the
  `[:bilimbi, :base, :audit, :capture_failure]` telemetry event.
  `WriteCapture.without_capture/1` does not silence this seam — a console
  command is always somebody's decision.
  """

  alias Bilimbi.Base.Database.WriteCapture

  @typedoc """
  Which guard refused the command.

    * `:operator` — the caller did not assert the platform-operator tenant;
    * `:empty` — nothing was submitted;
    * `:statement` — the first word was not `SELECT` or `WITH`;
    * `:keyword` — the text carried a write or DDL keyword;
    * `:read_only_transaction` — PostgreSQL refused a write inside the
      executor's `READ ONLY` transaction.
  """
  @type guard :: :operator | :empty | :statement | :keyword | :read_only_transaction

  @typedoc """
  What became of the command.

  A succeeded command carries the number of rows the query matched, a
  refused one the guard and its message, a failed one the database's
  error message.
  """
  @type outcome ::
          {:succeeded, non_neg_integer()}
          | {:refused, guard(), String.t()}
          | {:failed, String.t()}

  @doc """
  Invoked after every console command.

  `sql` is the text as submitted, before trimming. `meta` carries the
  caller's `:name` option when it passed one.
  """
  @callback after_console_command(sql :: String.t(), outcome(), meta :: map()) :: :ok

  @doc false
  @spec dispatch(String.t(), outcome(), keyword()) :: :ok
  def dispatch(sql, outcome, opts) when is_binary(sql) and is_list(opts) do
    capture = Application.get_env(:bilimbi_base_database, :console_capture)

    if capture do
      meta = if name = Keyword.get(opts, :name), do: %{name: name}, else: %{}
      capture.after_console_command(sql, outcome, meta)
    end

    :ok
  rescue
    error ->
      WriteCapture.capture_failed(:console_command, __MODULE__, error, __STACKTRACE__)
  end
end
