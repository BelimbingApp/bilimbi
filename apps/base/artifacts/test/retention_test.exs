defmodule Bilimbi.Base.Artifacts.RetentionTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.{Artifacts, Audit, Settings, Tenancy}
  alias Bilimbi.Base.Artifacts.{RetentionEvent, Schema, TestOwner}
  import Bilimbi.Base.Artifacts.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures
  import Bilimbi.Base.Settings.TestFixtures
  import Bilimbi.Base.Audit.TestFixtures

  @seven_years DateTime.add(~U[2026-10-13 00:00:00.000000Z], 7 * 365, :day)

  setup do
    registry = Bilimbi.Base.ModuleRegistry.ContributionRegistry

    settings =
      Bilimbi.Base.Settings.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/artifacts"},
          payload: Bilimbi.Base.Artifacts.Contributions.contributions().settings
        }
      ])

    principals =
      Bilimbi.Base.Tenancy.SystemPrincipals.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "test/retention", otp_app: :bilimbi_base_artifacts},
          payload: [
            %{
              name: "retention.records_officer",
              description: "Places legal holds for the retention test.",
              capabilities: ["test.retention.hold"]
            }
          ]
        }
      ])

    registry.put_consumers_for_test!(%{settings: settings, system_principals: principals})

    on_exit(&registry.clear_for_test!/0)
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    create_settings_table!()
    create_audit_tables!()
    create_artifacts_table!()
    root = Path.expand("tmp/artifacts-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    Settings.put("artifacts.storage_root", root)
    Settings.put("artifacts.retention_days", 30)
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope, root: root, ref: %{subject: "statement-2026-09", kind: "bank_statement"}}
  end

  test "verifies the owned schema contract with its guard triggers" do
    assert :ok =
             Bilimbi.Base.Artifacts.SchemaContract.verify_invariants(Repo,
               prefix: temporary_schema!()
             )
  end

  test "a disabled guard trigger is drift" do
    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE base_artifacts DISABLE TRIGGER base_artifacts_retention_guard",
      []
    )

    assert {:error, [error]} =
             Bilimbi.Base.Artifacts.SchemaContract.verify_invariants(Repo,
               prefix: temporary_schema!()
             )

    assert error =~ "retention guard triggers differ"
  end

  test "an ordinary document is unchanged: expiry, purge and metadata", c do
    assert {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    assert %DateTime{} = doc.expires_at
    assert doc.retain_until == nil
    assert doc.legal_hold_at == nil
    refute_received {:authorized, :retain, _, _}
    assert {:ok, []} = Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)
    assert {:ok, :deleted} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
  end

  test "retention at creation keeps the document readable past the operator expiry", c do
    Settings.put("artifacts.retention_days", 1)
    user_scope = Tenancy.Authentication.sign_in(c.scope, 71, 51)

    assert {:ok, doc} =
             Artifacts.put(user_scope, 51, TestOwner, c.ref, "statement", "application/pdf",
               retain_until: @seven_years,
               reason: "Income Tax Act 1967 s.82"
             )

    assert_received {:authorized, :retain, 51, _}
    assert doc.retain_until == @seven_years
    assert doc.expires_at == nil
    assert doc.legal_hold_at == nil

    # Well past the operator period, and still readable.
    assert {:ok, %{bytes: "statement", metadata: ^doc}} =
             Artifacts.read(user_scope, 51, TestOwner, doc.id)

    assert {:ok, %{deleted: [], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    assert File.exists?(Path.join(c.root, doc.id))

    assert {:ok, [event]} = Artifacts.retention_history(user_scope, 51, TestOwner, doc.id)

    assert %{
             event: "retained",
             retain_until: @seven_years,
             legal_hold: false,
             reason: "Income Tax Act 1967 s.82",
             actor_type: "user",
             actor_id: 71,
             impersonator_id: nil,
             system_principal: nil,
             recorded_at: %DateTime{} = recorded_at
           } = event

    assert abs(DateTime.diff(recorded_at, DateTime.utc_now(), :second)) < 60

    {:ok, actions} = Audit.list_actions(c.scope)
    assert [action] = Enum.filter(actions, &(&1.event == "artifacts.retained"))
    assert action.actor_id == 71

    assert action.payload == %{
             "artifact_id" => doc.id,
             "owner_id" => "test/documents",
             "retain_until" => DateTime.to_iso8601(@seven_years),
             "legal_hold" => false
           }
  end

  test "the database, not the application, stamps the event time", c do
    {:ok, doc} =
      Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years
      )

    forged = ~U[2000-01-01 00:00:00.000000Z]
    row = Repo.get!(Schema, doc.id)

    {:ok, event} =
      Repo.insert(
        RetentionEvent.changeset(%{
          artifact_id: row.id,
          tenant_id: row.tenant_id,
          company_id: row.company_id,
          owner_id: row.owner_id,
          event: "retention_extended",
          retain_until: @seven_years,
          legal_hold: false,
          actor_type: "guest",
          actor_id: 0,
          recorded_at: forged
        })
      )

    assert DateTime.compare(event.recorded_at, forged) == :gt
    assert abs(DateTime.diff(event.recorded_at, DateTime.utc_now(), :second)) < 60
  end

  test "retention is refused for invalid requests, reservations and without the owner's grant",
       c do
    past = DateTime.add(DateTime.utc_now(), -1, :second)

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
               retain_until: past
             )

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
               retain_until: @seven_years,
               legal_hold: "yes"
             )

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
               retain_until: @seven_years,
               reason: String.duplicate("x", 256)
             )

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain", legal_hold: true)

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain", unknown: true)

    assert Repo.aggregate(Schema, :count) == 0

    Process.put({:deny, :retain}, true)

    assert {:error, :forbidden} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
               retain_until: @seven_years
             )

    assert Repo.aggregate(Schema, :count) == 0
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert {:error, :forbidden} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years)

    assert {:error, :forbidden} = Artifacts.place_hold(c.scope, 51, TestOwner, doc.id)
    Process.put({:deny, :retain}, false)

    assert {:error, :invalid_retention} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, past)

    assert {:error, :invalid_retention} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years, unknown: true)

    Repo.get!(Schema, doc.id) |> change(ready_at: nil) |> Repo.update!()

    assert {:error, :not_found} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years)

    assert {:ok, []} = Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)
    assert Repo.aggregate(RetentionEvent, :count) == 0
  end

  test "a second-precision retain-until is stored and a non-UTC one is refused whole", c do
    whole_second = ~U[2033-10-13 23:59:59Z]
    stored = ~U[2033-10-13 23:59:59.000000Z]

    assert {:ok, doc} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
               retain_until: whole_second
             )

    assert doc.retain_until == stored
    assert Repo.get!(Schema, doc.id).retain_until == stored

    later = ~U[2034-10-13 23:59:59Z]
    assert {:ok, extended} = Artifacts.retain(c.scope, 51, TestOwner, doc.id, later)
    assert extended.retain_until == ~U[2034-10-13 23:59:59.000000Z]

    shifted = %{@seven_years | time_zone: "Asia/Kuala_Lumpur", utc_offset: 28_800, zone_abbr: "+08"}

    assert {:error, :invalid_retention} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "other", "text/plain",
               retain_until: shifted
             )

    assert Repo.aggregate(Schema, :count) == 1
    assert File.ls!(c.root) == [doc.id]

    {:ok, plain} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "plain", "text/plain")

    assert {:error, :invalid_retention} =
             Artifacts.retain(c.scope, 51, TestOwner, plain.id, shifted)

    assert Repo.get!(Schema, plain.id).retain_until == nil
  end

  test "a document retained later loses its expiry and can only be extended", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    later = DateTime.add(@seven_years, 1, :day)

    assert {:ok, retained} = Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years)
    assert retained.expires_at == nil
    assert retained.retain_until == @seven_years

    assert {:error, :retention_not_extended} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years)

    assert {:error, :retention_not_extended} =
             Artifacts.retain(
               c.scope,
               51,
               TestOwner,
               doc.id,
               DateTime.add(@seven_years, -1, :day)
             )

    assert {:ok, extended} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, later, reason: "audit reopened")

    assert extended.retain_until == later

    assert {:ok, events} = Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)
    assert Enum.map(events, & &1.event) == ["retained", "retention_extended"]
    assert Enum.map(events, & &1.retain_until) == [@seven_years, later]
    assert Enum.map(events, & &1.reason) == [nil, "audit reopened"]
    assert [first, second] = Enum.map(events, & &1.recorded_at)
    assert DateTime.compare(first, second) != :gt

    {:ok, actions} = Audit.list_actions(c.scope)
    events = Enum.frequencies(Enum.map(actions, & &1.event))
    assert events["artifacts.retained"] == 1
    assert events["artifacts.retention_extended"] == 1
  end

  test "deletion is refused before retain-until and allowed after it", c do
    {:ok, doc} =
      Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years
      )

    assert {:error, :retained} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
    assert_received {:authorized, :delete, 51, _}
    assert File.exists?(Path.join(c.root, doc.id))
    assert is_nil(Repo.get!(Schema, doc.id).deleted_at)
    {:ok, actions} = Audit.list_actions(c.scope)
    refute Enum.any?(actions, &(&1.event == "artifacts.delete"))

    # Retention lapsed: still readable, never purged by maintenance, and
    # deletable by an explicit, authorized call.
    lapse!(doc.id)
    assert {:ok, %{bytes: "bytes"}} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    assert {:ok, %{deleted: [], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    assert {:ok, :deleted} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
    refute File.exists?(Path.join(c.root, doc.id))
    assert {:error, :not_found} = Artifacts.read(c.scope, 51, TestOwner, doc.id)

    assert {:ok, [%{event: "retained"}]} =
             Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)
  end

  test "a legal hold blocks deletion past retain-until until it is released", c do
    user_scope = Tenancy.Authentication.sign_in(c.scope, 71, 51)

    {:ok, doc} =
      Artifacts.put(user_scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years,
        legal_hold: true
      )

    assert %DateTime{} = doc.legal_hold_at

    assert {:ok, [%{event: "retained", legal_hold: true}]} =
             Artifacts.retention_history(user_scope, 51, TestOwner, doc.id)

    assert {:error, :already_on_hold} = Artifacts.place_hold(user_scope, 51, TestOwner, doc.id)
    lapse!(doc.id)
    assert {:error, :legal_hold} = Artifacts.delete(user_scope, 51, TestOwner, doc.id)
    assert {:ok, %{bytes: "bytes"}} = Artifacts.read(user_scope, 51, TestOwner, doc.id)

    assert {:ok, released} =
             Artifacts.release_hold(user_scope, 51, TestOwner, doc.id, reason: "case closed")

    assert released.legal_hold_at == nil
    assert {:error, :not_on_hold} = Artifacts.release_hold(user_scope, 51, TestOwner, doc.id)
    assert {:ok, held} = Artifacts.place_hold(user_scope, 51, TestOwner, doc.id)
    assert %DateTime{} = held.legal_hold_at
    assert {:error, :legal_hold} = Artifacts.delete(user_scope, 51, TestOwner, doc.id)
    assert {:ok, _} = Artifacts.release_hold(user_scope, 51, TestOwner, doc.id)
    assert {:ok, :deleted} = Artifacts.delete(user_scope, 51, TestOwner, doc.id)

    assert {:ok, events} = Artifacts.retention_history(user_scope, 51, TestOwner, doc.id)

    assert Enum.map(events, &{&1.event, &1.legal_hold, &1.actor_id}) == [
             {"retained", true, 71},
             {"hold_released", false, 71},
             {"hold_placed", true, 71},
             {"hold_released", false, 71}
           ]

    assert Enum.map(events, & &1.reason) == [nil, "case closed", nil, nil]
    {:ok, actions} = Audit.list_actions(c.scope)
    frequencies = Enum.frequencies(Enum.map(actions, & &1.event))
    assert frequencies["artifacts.hold_placed"] == 1
    assert frequencies["artifacts.hold_released"] == 2
  end

  test "a legal hold needs a retained document", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    assert {:error, :not_retained} = Artifacts.place_hold(c.scope, 51, TestOwner, doc.id)
    assert {:error, :not_on_hold} = Artifacts.release_hold(c.scope, 51, TestOwner, doc.id)

    assert_raise Ecto.ConstraintError, ~r/base_artifacts_hold_requires_retention/, fn ->
      Repo.get!(Schema, doc.id)
      |> change(legal_hold_at: DateTime.utc_now())
      |> Repo.update!(mode: :savepoint)
    end
  end

  test "the database refuses deletion, purge and shortening behind the facade's back", c do
    {:ok, doc} =
      Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years
      )

    row = Repo.get!(Schema, doc.id)

    for changes <- [
          [deleted_at: DateTime.utc_now()],
          [purged_at: DateTime.utc_now()],
          [retain_until: DateTime.add(@seven_years, -1, :day)],
          [retain_until: nil, expires_at: DateTime.utc_now()]
        ] do
      assert_raise Ecto.ConstraintError, ~r/base_artifacts_retention_guard/, fn ->
        row |> change(changes) |> Repo.update!(mode: :savepoint)
      end
    end

    assert_raise Ecto.ConstraintError, ~r/base_artifacts_retention_guard/, fn ->
      Repo.delete!(row, mode: :savepoint)
    end

    assert_raise Ecto.ConstraintError, ~r/base_artifacts_retention_exclusive/, fn ->
      row |> change(expires_at: DateTime.utc_now()) |> Repo.update!(mode: :savepoint)
    end

    # Bulk writes meet the same trigger.
    assert_raise Postgrex.Error, ~r/is retained/, fn ->
      Ecto.Adapters.SQL.query!(Repo, "UPDATE base_artifacts SET deleted_at = now()", [])
    end

    # On hold past retain-until: still guarded.
    {:ok, _} = Artifacts.place_hold(c.scope, 51, TestOwner, doc.id)
    lapse!(doc.id)

    assert_raise Ecto.ConstraintError, ~r/base_artifacts_retention_guard/, fn ->
      Repo.get!(Schema, doc.id) |> change(deleted_at: DateTime.utc_now()) |> Repo.update!()
    end

    {:ok, _} = Artifacts.release_hold(c.scope, 51, TestOwner, doc.id)
    assert {:ok, :deleted} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
  end

  test "retention events are append-only in the database", c do
    {:ok, doc} =
      Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years
      )

    [event] = Repo.all(RetentionEvent)

    assert_raise Ecto.ConstraintError, ~r/base_artifact_retention_events_append_only/, fn ->
      event |> change(reason: "rewritten") |> Repo.update!(mode: :savepoint)
    end

    assert_raise Ecto.ConstraintError, ~r/base_artifact_retention_events_append_only/, fn ->
      Repo.delete!(event, mode: :savepoint)
    end

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Ecto.Adapters.SQL.query!(Repo, "DELETE FROM base_artifact_retention_events", [])
    end

    assert_raise Ecto.ConstraintError, ~r/base_artifact_retention_events_artifact_id_fkey/, fn ->
      lapse!(doc.id)
      Repo.delete!(Repo.get!(Schema, doc.id), mode: :savepoint)
    end

    assert {:ok, [%{event: "retained"}]} =
             Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)
  end

  test "a system principal and an impersonator are named on the event", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    impersonating =
      Tenancy.Authentication.sign_in(c.scope, 71, 51,
        impersonator_id: 9,
        impersonation_session_id: "s"
      )

    assert {:ok, _} = Artifacts.retain(impersonating, 51, TestOwner, doc.id, @seven_years)

    {:ok, token} =
      Tenancy.Authentication.delegate_system(c.scope, "retention.records_officer", 51)

    {:ok, system} = Tenancy.Authentication.resume_system(token)
    assert {:ok, _} = Artifacts.place_hold(system, 51, TestOwner, doc.id)

    assert {:ok, [user_event, system_event]} =
             Artifacts.retention_history(c.scope, 51, TestOwner, doc.id)

    assert %{actor_type: "user", actor_id: 71, impersonator_id: 9} = user_event

    assert %{actor_type: "system", actor_id: 0, system_principal: "retention.records_officer"} =
             system_event
  end

  test "retention operations stay scoped to tenant, company and adapter", c do
    {:ok, doc} =
      Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain",
        retain_until: @seven_years
      )

    {:ok, other_scope} = Tenancy.scope(41)
    insert_tenant!(%{id: 42, is_platform_operator: false})
    {:ok, other_tenant} = Tenancy.scope(42)

    for {scope, company, owner} <- [
          {other_scope, 52, TestOwner},
          {other_tenant, 51, TestOwner},
          {c.scope, 51, Bilimbi.Base.Artifacts.OtherTestOwner}
        ] do
      assert {:error, :not_found} = Artifacts.retain(scope, company, owner, doc.id, @seven_years)
      assert {:error, :not_found} = Artifacts.place_hold(scope, company, owner, doc.id)
      assert {:error, :not_found} = Artifacts.release_hold(scope, company, owner, doc.id)
      assert {:error, :not_found} = Artifacts.retention_history(scope, company, owner, doc.id)
    end

    user_scope = Tenancy.Authentication.sign_in(c.scope, 71, 52)

    assert {:error, :forbidden} =
             Artifacts.retain(user_scope, 51, TestOwner, doc.id, @seven_years)

    assert {:error, :forbidden} = Artifacts.retention_history(user_scope, 51, TestOwner, doc.id)
    assert Repo.aggregate(RetentionEvent, :count) == 1
  end

  test "retention operations refuse an outer transaction", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    for operation <- [
          fn -> Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years) end,
          fn -> Artifacts.place_hold(c.scope, 51, TestOwner, doc.id) end,
          fn -> Artifacts.release_hold(c.scope, 51, TestOwner, doc.id) end
        ] do
      assert_raise ArgumentError, ~r/committed filesystem boundary/, fn ->
        Repo.transact(operation)
      end
    end
  end

  test "an unavailable action audit prevents a retention change", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    Ecto.Adapters.SQL.query!(Repo, "DROP TABLE base_audit_actions", [])

    assert {:error, :audit_unavailable} =
             Artifacts.retain(c.scope, 51, TestOwner, doc.id, @seven_years)

    assert is_nil(Repo.get!(Schema, doc.id).retain_until)
    assert Repo.aggregate(RetentionEvent, :count) == 0
  end

  # Fast-forwards the clock: moves retain-until into the past with the guard
  # switched off, since neither the facade nor the database ever shortens it.
  defp lapse!(id) do
    for sql <- [
          "ALTER TABLE base_artifacts DISABLE TRIGGER base_artifacts_retention_guard",
          "UPDATE base_artifacts SET retain_until = timezone('UTC', now()) - interval '1 second' " <>
            "WHERE id = '#{id}'",
          "ALTER TABLE base_artifacts ENABLE TRIGGER base_artifacts_retention_guard"
        ],
        do: Ecto.Adapters.SQL.query!(Repo, sql, [])
  end
end
