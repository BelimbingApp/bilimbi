defmodule Bilimbi.Base.Database.WriteCaptureTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database.WriteCapture
  alias Ecto.Adapters.SQL

  defmodule Row do
    use Ecto.Schema

    import Ecto.Changeset

    schema "write_capture_rows" do
      field :name, :string
      field :tenant_id, :id
    end

    def changeset(row, attributes), do: cast(row, attributes, [:name, :tenant_id])
  end

  defmodule RecordingCapture do
    @behaviour Bilimbi.Base.Database.WriteCapture

    @impl true
    def after_write(action, source, result) do
      send(Process.get(:capture_test_pid), {:captured, action, source, result})
      :ok
    end
  end

  defmodule RaisingCapture do
    @behaviour Bilimbi.Base.Database.WriteCapture

    @impl true
    def after_write(_action, _source, _result), do: raise("capture exploded")
  end

  setup do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS write_capture_rows (
        id bigserial PRIMARY KEY,
        name varchar(255),
        tenant_id bigint
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    previous = Application.get_env(:bilimbi_base_database, :write_capture)
    Application.put_env(:bilimbi_base_database, :write_capture, RecordingCapture)
    Process.put(:capture_test_pid, self())

    on_exit(fn -> Application.put_env(:bilimbi_base_database, :write_capture, previous) end)
    :ok
  end

  test "successful struct writes dispatch with source and result" do
    {:ok, row} = Repo.insert(Row.changeset(%Row{}, %{name: "one"}))
    assert_receive {:captured, :insert, %Ecto.Changeset{}, %Row{name: "one"}}

    {:ok, updated} = Repo.update(Row.changeset(row, %{name: "two"}))
    assert_receive {:captured, :update, %Ecto.Changeset{changes: %{name: "two"}}, %Row{}}

    {:ok, _deleted} = Repo.delete(updated)
    assert_receive {:captured, :delete, %Row{}, %Row{name: "two"}}
  end

  test "bang variants and default-arity calls dispatch too" do
    row = Repo.insert!(Row.changeset(%Row{}, %{name: "bang"}))
    assert_receive {:captured, :insert, _source, %Row{name: "bang"}}

    Repo.update!(Row.changeset(row, %{name: "bang2"}))
    assert_receive {:captured, :update, _source, %Row{name: "bang2"}}

    Repo.delete!(row)
    assert_receive {:captured, :delete, _source, %Row{}}
  end

  test "insert_or_update dispatches the action the changeset state implies" do
    {:ok, row} = Repo.insert_or_update(Row.changeset(%Row{}, %{name: "new"}))
    assert_receive {:captured, :insert, _source, %Row{name: "new"}}

    {:ok, _row} = Repo.insert_or_update(Row.changeset(row, %{name: "grown"}))
    assert_receive {:captured, :update, _source, %Row{name: "grown"}}
  end

  test "a failed write dispatches nothing" do
    invalid = %Row{} |> Row.changeset(%{name: "x"}) |> Ecto.Changeset.add_error(:name, "no")
    assert {:error, _changeset} = Repo.insert(invalid)
    refute_receive {:captured, _action, _source, _result}
  end

  test "without_capture suppresses dispatch and restores the previous state" do
    WriteCapture.without_capture(fn ->
      assert WriteCapture.disabled?()
      Repo.insert!(Row.changeset(%Row{}, %{name: "silent"}))
    end)

    refute WriteCapture.disabled?()
    refute_receive {:captured, _action, _source, _result}

    Repo.insert!(Row.changeset(%Row{}, %{name: "loud"}))
    assert_receive {:captured, :insert, _source, %Row{name: "loud"}}
  end

  test "a raising capture is contained: the write succeeds and telemetry counts it" do
    Application.put_env(:bilimbi_base_database, :write_capture, RaisingCapture)

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
        assert %Row{name: "kept"} = Repo.insert!(Row.changeset(%Row{}, %{name: "kept"}))
      end)

    assert log =~ "audit write capture failed"
    assert_receive {:capture_failure, %{count: 1}, %{action: :insert, schema: Row}}
    assert Repo.get_by(Row, name: "kept")
  end

  test "dispatch itself runs with capture disabled, so a capture's own writes cannot recurse" do
    defmodule SelfWritingCapture do
      @behaviour Bilimbi.Base.Database.WriteCapture

      @impl true
      def after_write(_action, _source, %{name: "origin"}) do
        # This nested write must not re-enter capture.
        Bilimbi.Base.Repo.insert!(
          Bilimbi.Base.Database.WriteCaptureTest.Row.changeset(
            %Bilimbi.Base.Database.WriteCaptureTest.Row{},
            %{name: "echo"}
          )
        )

        send(Process.get(:capture_test_pid), :self_write_done)
        :ok
      end

      def after_write(_action, _source, _result) do
        send(Process.get(:capture_test_pid), :recursed)
        :ok
      end
    end

    Application.put_env(:bilimbi_base_database, :write_capture, SelfWritingCapture)

    Repo.insert!(Row.changeset(%Row{}, %{name: "origin"}))

    assert_receive :self_write_done
    refute_receive :recursed
  end
end
