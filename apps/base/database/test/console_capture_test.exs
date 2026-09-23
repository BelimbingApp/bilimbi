defmodule Bilimbi.Base.Database.ConsoleCaptureTest do
  @moduledoc """
  Every command handed to the executor reaches the console-capture seam
  with its outcome, whatever that outcome is, and the capture never sees a
  result row.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Repo

  defmodule RecordingCapture do
    @behaviour Bilimbi.Base.Database.ConsoleCapture

    @impl true
    def after_console_command(sql, outcome, meta) do
      send(Process.get(:console_capture_test_pid), {:captured, sql, outcome, meta})
      :ok
    end
  end

  defmodule RaisingCapture do
    @behaviour Bilimbi.Base.Database.ConsoleCapture

    @impl true
    def after_console_command(_sql, _outcome, _meta), do: raise("console capture exploded")
  end

  setup do
    previous = Application.get_env(:bilimbi_base_database, :console_capture)
    Application.put_env(:bilimbi_base_database, :console_capture, RecordingCapture)
    Process.put(:console_capture_test_pid, self())

    on_exit(fn -> Application.put_env(:bilimbi_base_database, :console_capture, previous) end)
    :ok
  end

  defp as_operator(sql, params \\ %{}, opts \\ []) do
    Database.execute_readonly(sql, params, Keyword.put(opts, :operator, true))
  end

  test "a succeeded command dispatches its row count and never its rows" do
    sql = "SELECT 'needle-one' AS needle UNION ALL SELECT 'needle-two'"

    assert {:ok, %{total: 2}} = as_operator(sql)
    assert_receive {:captured, ^sql, {:succeeded, 2} = outcome, %{}}
    refute inspect(outcome) =~ "needle"
  end

  test "the text is dispatched as submitted, before trimming" do
    sql = "  SELECT 1 AS one;  "

    assert {:ok, _result} = as_operator(sql)
    assert_receive {:captured, ^sql, {:succeeded, 1}, %{}}
  end

  test "a caller's name travels with the command and plays no part in it" do
    assert {:ok, _result} = as_operator("SELECT 1", %{}, name: "Ones")
    assert_receive {:captured, "SELECT 1", {:succeeded, 1}, %{name: "Ones"}}
  end

  test "each guard's refusal names the guard and carries the message the caller got" do
    assert {:error, statement} = as_operator("DELETE FROM users")
    assert_receive {:captured, "DELETE FROM users", {:refused, :statement, ^statement}, %{}}

    assert {:error, keyword} = as_operator("SELECT 1; DELETE FROM users")
    assert_receive {:captured, _sql, {:refused, :keyword, ^keyword}, %{}}

    assert {:error, empty} = as_operator("   ")
    assert_receive {:captured, "   ", {:refused, :empty, ^empty}, %{}}

    assert {:error, operator} = Database.execute_readonly("SELECT 1", %{}, [])
    assert_receive {:captured, "SELECT 1", {:refused, :operator, ^operator}, %{}}
    assert operator =~ "platform operator"
  end

  test "a write PostgreSQL refuses inside the read-only transaction is a refusal by that guard" do
    Repo.query!("CREATE SEQUENCE __blb_console_capture_probe START 1")
    sql = "SELECT setval('__blb_console_capture_probe', 42)"

    assert {:error, message} = as_operator(sql)
    assert message =~ "read-only transaction"
    assert_receive {:captured, ^sql, {:refused, :read_only_transaction, ^message}, %{}}
  end

  test "a failed command dispatches the database's error message" do
    sql = "SELECT * FROM __blb_absent_console_table"

    assert {:error, message} = as_operator(sql)
    assert message =~ "does not exist"
    assert_receive {:captured, ^sql, {:failed, ^message}, %{}}
  end

  test "a raising capture is contained: the answer stands and telemetry counts it" do
    Application.put_env(:bilimbi_base_database, :console_capture, RaisingCapture)

    handler_id = {__MODULE__, :failure}
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:bilimbi, :base, :audit, :capture_failure],
        fn _event, measurements, metadata, _config ->
          send(parent, {:capture_failure, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{rows: [%{"one" => 1}]}} = as_operator("SELECT 1 AS one")
      end)

    assert log =~ "console capture exploded"

    assert_receive {:capture_failure, %{count: 1},
                    %{action: :console_command, schema: Bilimbi.Base.Database.ConsoleCapture}}
  end

  test "an unconfigured seam leaves the executor's answers unchanged" do
    Application.put_env(:bilimbi_base_database, :console_capture, nil)

    assert {:ok, %{total: 1}} = as_operator("SELECT 1")
    assert {:error, _message} = as_operator("DELETE FROM users")
    refute_receive {:captured, _sql, _outcome, _meta}
  end
end
