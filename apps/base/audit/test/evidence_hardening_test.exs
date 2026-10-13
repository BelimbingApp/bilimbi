defmodule Bilimbi.Base.Audit.EvidenceHardeningTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.MutationCapture
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Ecto.Adapters.SQL

  setup do
    TestFixtures.create_audit_tables!()
    TenancyFixtures.create_scoped_records_table!()
    previous = Application.get_env(:bilimbi_base_database, :write_capture)
    Application.put_env(:bilimbi_base_database, :write_capture, MutationCapture)
    on_exit(fn -> Application.put_env(:bilimbi_base_database, :write_capture, previous) end)
    :ok
  end

  test "schema verification requires enabled evidence guards after hardening" do
    prefix = temporary_schema!()
    assert :ok = Bilimbi.Base.Audit.SchemaContract.verify_invariants(Repo, prefix: prefix)

    SQL.query!(
      Repo,
      "ALTER TABLE base_audit_mutations DISABLE TRIGGER base_audit_mutations_evidence_guard",
      []
    )

    assert {:error, errors} =
             Bilimbi.Base.Audit.SchemaContract.verify_invariants(Repo, prefix: prefix)

    assert "base_audit_mutations: missing or disabled evidence_guard" in errors
  end

  test "database stamps recording time independently of caller event time" do
    [[before]] = SQL.query!(Repo, "SELECT clock_timestamp() AT TIME ZONE 'UTC'", []).rows

    assert {:ok, action} =
             Audit.record_action(:unscoped, %{
               event: "historical",
               occurred_at: ~N[2000-01-01 00:00:00]
             })

    [[after_time]] = SQL.query!(Repo, "SELECT clock_timestamp() AT TIME ZONE 'UTC'", []).rows

    assert [[stamped]] =
             SQL.query!(
               Repo,
               "INSERT INTO base_audit_actions (event, actor_type, actor_id, recorded_at) VALUES ('spoof', 'unknown', 0, '2000-01-01') RETURNING recorded_at",
               []
             ).rows

    assert NaiveDateTime.compare(stamped, before) != :lt
    assert action.actor_type == "unknown"
    assert action.occurred_at == ~N[2000-01-01 00:00:00]
    assert NaiveDateTime.compare(action.recorded_at, before) != :lt
    assert NaiveDateTime.compare(action.recorded_at, after_time) != :gt
  end

  test "PostgreSQL rejects evidence updates, deletes and truncation" do
    {:ok, _} = Audit.record_action(:unscoped, %{event: "immutable"})
    Repo.insert!(%TenancyFixtures.ScopedRecord{label: "evidence", tenant_id: 41})

    for table <- ~w(base_audit_actions base_audit_mutations base_audit_capture_failures),
        statement <- [
          "UPDATE #{table} SET actor_id = 123",
          "DELETE FROM #{table}",
          "TRUNCATE #{table} CASCADE"
        ] do
      # Failure table needs a row for row-level rejection to run.
      if table == "base_audit_capture_failures" do
        MutationCapture.capture_failure(:insert, TenancyFixtures.ScopedRecord, RuntimeError)
      end

      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               SQL.query(Repo, statement, [], mode: :savepoint)
    end
  end

  test "direct facade inherits the scope's actor and impersonator without process context" do
    scope =
      TenancyFixtures.scope(41)
      |> Authentication.sign_in(91, 73,
        impersonator_id: 92,
        impersonation_session_id: "borrowed-session"
      )

    Context.put(nil)
    {:ok, action} = Audit.record_action(scope, %{event: "direct"})
    assert action.actor_type == "user"
    assert action.actor_id == 91
    assert action.impersonator_id == 92
    assert action.company_id == 73
    assert action.tenant_id == 41
    assert Context.get().actor_type == "unknown"
  end

  test "background scope attributes both struct and bulk writes and restores context" do
    scope =
      TenancyFixtures.scope(41)
      |> Authentication.sign_in(91, 73,
        impersonator_id: 92,
        impersonation_session_id: "borrowed-session"
      )

    parent = self()

    task =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())

        Audit.with_scope(scope, fn ->
          Repo.insert!(%TenancyFixtures.ScopedRecord{label: "job", tenant_id: 41})
          Repo.insert_all(TenancyFixtures.ScopedRecord, [%{label: "bulk", tenant_id: 41}])
        end)

        Context.get()
      end)

    assert %Context{actor_type: "unknown"} = Task.await(task)
    assert [_, _] = rows = Repo.all(MutationSchema)
    assert Enum.all?(rows, &match?(%{actor_type: "user", actor_id: 91, impersonator_id: 92}, &1))
    assert Enum.all?(rows, & &1.recorded_at)
  end

  test "failure is durable and alerted while the business write survives" do
    # A real database constraint refuses capture while its business write survives.
    handler = {__MODULE__, make_ref()}
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :audit, :capture_alert],
      fn _, _, metadata, _ -> send(parent, {:alert, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    SQL.query!(
      Repo,
      "ALTER TABLE base_audit_mutations ADD CONSTRAINT refuse_capture CHECK (actor_id < 0)",
      []
    )

    ExUnit.CaptureLog.capture_log(fn ->
      Repo.transaction(fn ->
        assert %{label: "kept"} =
                 Repo.insert!(%TenancyFixtures.ScopedRecord{label: "kept", tenant_id: 41})
      end)
    end)

    assert_receive {:alert, %{durable: true}}

    assert [["unknown", 0, "Ecto.ConstraintError"]] =
             SQL.query!(
               Repo,
               "SELECT actor_type, actor_id, error_type FROM base_audit_capture_failures",
               []
             ).rows

    assert Repo.get_by(TenancyFixtures.ScopedRecord, label: "kept")
  end

  test "strict capture rolls back an enclosing transaction and restores its mode" do
    SQL.query!(
      Repo,
      "ALTER TABLE base_audit_mutations ADD CONSTRAINT refuse_capture CHECK (actor_id < 0)",
      []
    )

    ExUnit.CaptureLog.capture_log(fn ->
      assert_raise Bilimbi.Base.Database.CaptureError, fn ->
        Repo.transaction(fn ->
          Audit.with_strict_capture(fn ->
            Repo.insert!(%TenancyFixtures.ScopedRecord{label: "strict", tenant_id: 41})
          end)
        end)
      end

      refute Repo.get_by(TenancyFixtures.ScopedRecord, label: "strict")

      assert %{label: "best effort"} =
               Repo.insert!(%TenancyFixtures.ScopedRecord{label: "best effort", tenant_id: 41})
    end)
  end
end
