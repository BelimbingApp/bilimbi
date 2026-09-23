defmodule Bilimbi.Base.Database.WriteCaptureTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Ecto.Query

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

  defmodule ExcludedRow do
    use Ecto.Schema

    schema "write_capture_rows" do
      field :name, :string
      field :tenant_id, :id
    end
  end

  defmodule RecordingCapture do
    @behaviour Bilimbi.Base.Database.WriteCapture

    @impl true
    def after_write(action, source, result) do
      send(Process.get(:capture_test_pid), {:captured, action, source, result})
      :ok
    end

    @impl true
    def after_bulk_write(schema, changes) do
      send(Process.get(:capture_test_pid), {:captured_bulk, schema, changes})
      :ok
    end

    # The excluded schema this suite uses to prove a bulk write on one is
    # never even read, let alone recorded.
    @impl true
    def capture_schema?(schema),
      do: schema != Bilimbi.Base.Database.WriteCaptureTest.ExcludedRow
  end

  defmodule RaisingCapture do
    @behaviour Bilimbi.Base.Database.WriteCapture

    @impl true
    def after_write(_action, _source, _result), do: raise("capture exploded")

    @impl true
    def after_bulk_write(_schema, _changes), do: raise("bulk capture exploded")

    @impl true
    def capture_schema?(_schema), do: true
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

    SQL.query!(Repo, "DELETE FROM write_capture_rows", [])

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

  describe "query-based bulk writes" do
    test "insert_all dispatches one change per inserted row" do
      assert {2, nil} =
               Repo.insert_all(Row, [%{name: "alpha"}, %{name: "beta", tenant_id: 7}])

      assert_receive {:captured_bulk, Row, changes}
      assert [{:insert, nil, %Row{name: "alpha"}}, {:insert, nil, %Row{name: "beta"}}] = changes
    end

    test "delete_all dispatches the deleted rows as the old values" do
      Repo.insert_all(Row, [%{name: "doomed"}])
      assert_receive {:captured_bulk, Row, _inserted}

      assert {1, nil} = Repo.delete_all(Row)

      assert_receive {:captured_bulk, Row, [{:delete, %Row{name: "doomed"}, nil}]}
    end

    test "update_all pairs a pre-read against the new rows" do
      Repo.insert_all(Row, [%{name: "before"}])
      assert_receive {:captured_bulk, Row, _inserted}

      assert {1, nil} = Repo.update_all(Row, set: [name: "after"])

      assert_receive {:captured_bulk, Row, [{:update, %Row{name: "before"}, %Row{name: "after"}}]}
    end

    test "a replacing upsert on an existing row is an update, not a creation" do
      SQL.query!(
        Repo,
        "CREATE UNIQUE INDEX IF NOT EXISTS write_capture_rows_name ON write_capture_rows (name)",
        []
      )

      on_exit(fn -> SQL.query!(Repo, "DROP INDEX IF EXISTS write_capture_rows_name", []) end)

      upsert = fn tenant ->
        Repo.insert_all(Row, [%{name: "same", tenant_id: tenant}],
          on_conflict: {:replace, [:tenant_id]},
          conflict_target: [:name]
        )
      end

      upsert.(1)
      assert_receive {:captured_bulk, Row, [{:insert, nil, %Row{tenant_id: 1}}]}

      upsert.(2)

      assert_receive {:captured_bulk, Row, [{:update, %Row{tenant_id: 1}, %Row{tenant_id: 2}}]}
    end

    test "an unclassifiable upsert is reported, and the write still succeeds" do
      handler_id = {__MODULE__, :unclassifiable}
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

      SQL.query!(
        Repo,
        "CREATE UNIQUE INDEX IF NOT EXISTS write_capture_rows_fragment " <>
          "ON write_capture_rows (name) WHERE tenant_id IS NOT NULL",
        []
      )

      on_exit(fn -> SQL.query!(Repo, "DROP INDEX IF EXISTS write_capture_rows_fragment", []) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {1, nil} =
                   Repo.insert_all(Row, [%{name: "fragmented", tenant_id: 3}],
                     on_conflict: {:replace, [:tenant_id]},
                     conflict_target: {:unsafe_fragment, "(name) WHERE tenant_id IS NOT NULL"}
                   )
        end)

      assert log =~ "cannot be told from an insert"
      assert_receive {:capture_failure, %{count: 1}, %{action: :insert, schema: Row}}
      refute_receive {:captured_bulk, _schema, _changes}
      assert Repo.get_by(Row, name: "fragmented")
    end

    test "an excluded schema is neither read nor dispatched" do
      assert {1, nil} = Repo.insert_all(ExcludedRow, [%{name: "quiet"}])
      assert {1, nil} = Repo.update_all(ExcludedRow, set: [name: "still quiet"])
      assert {1, nil} = Repo.delete_all(ExcludedRow)

      refute_receive {:captured_bulk, _schema, _changes}
    end

    test "without_capture suppresses bulk writes too" do
      WriteCapture.without_capture(fn ->
        Repo.insert_all(Row, [%{name: "silent"}])
        Repo.update_all(Row, set: [name: "silent again"])
        Repo.delete_all(Row)
      end)

      refute_receive {:captured_bulk, _schema, _changes}
    end

    test "the caller's returning option is honoured, not the one capture needs" do
      assert {1, [%Row{id: id, name: "asked"}]} =
               Repo.insert_all(Row, [%{name: "asked"}], returning: true)

      assert is_integer(id)

      assert {1, [%Row{id: only_id, name: nil}]} =
               Repo.insert_all(Row, [%{name: "narrow"}], returning: [:id])

      assert is_integer(only_id)
    end

    test "a query carrying its own select keeps its rows and is still captured" do
      Repo.insert_all(Row, [%{name: "selected"}])
      assert_receive {:captured_bulk, Row, _inserted}

      assert {1, ["selected"]} =
               Repo.delete_all(from(row in Row, select: row.name))

      assert_receive {:captured_bulk, Row, [{:delete, %Row{name: "selected"}, nil}]}
    end

    test "a bulk write matching nothing dispatches nothing" do
      assert {0, nil} = Repo.delete_all(from(row in Row, where: row.name == "absent"))

      assert {0, nil} =
               Repo.update_all(from(row in Row, where: row.name == "absent"), set: [name: "x"])

      refute_receive {:captured_bulk, _schema, _changes}
    end

    test "a raising bulk capture is contained: the write stands and telemetry counts it" do
      Application.put_env(:bilimbi_base_database, :write_capture, RaisingCapture)

      handler_id = {__MODULE__, :bulk_failure}
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
          assert {1, nil} = Repo.insert_all(Row, [%{name: "kept in bulk"}])
        end)

      assert log =~ "audit write capture failed"
      assert_receive {:capture_failure, %{count: 1}, %{action: :bulk, schema: Row}}
      assert Repo.get_by(Row, name: "kept in bulk")
    end
  end
end
