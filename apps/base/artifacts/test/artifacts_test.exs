defmodule Bilimbi.Base.ArtifactsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.{Artifacts, Audit, Settings, Tenancy}
  alias Bilimbi.Base.Artifacts.{Schema, TestOwner}
  import Bilimbi.Base.Artifacts.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures
  import Bilimbi.Base.Settings.TestFixtures
  import Bilimbi.Base.Audit.TestFixtures

  setup do
    registry = Bilimbi.Base.ModuleRegistry.ContributionRegistry

    settings =
      Bilimbi.Base.Settings.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/artifacts"},
          payload: Bilimbi.Base.Artifacts.Contributions.contributions().settings
        }
      ])

    registry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{settings: settings}
    })

    on_exit(&registry.clear_for_test!/0)
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, is_platform_operator: false})
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
    %{scope: scope, root: root, ref: %{subject: "record-1", kind: "evidence"}}
  end

  test "verifies the owned schema contract" do
    assert :ok =
             Bilimbi.Base.Database.SchemaVerifier.verify(
               Repo,
               Bilimbi.Base.Artifacts.SchemaContract.artifact_tables(),
               prefix: temporary_schema!()
             )
  end

  test "compatible adoption allows absence but refuses a partial Bilimbi-only artifact table" do
    prefix = temporary_schema!()
    Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE base_artifacts DROP COLUMN ready_at", [])

    assert {:error, errors} =
             Bilimbi.Base.Artifacts.SchemaContract.verify_invariants(Repo, prefix: prefix)

    assert Enum.any?(errors, &String.contains?(&1, "ready_at"))
    Ecto.Adapters.SQL.query!(Repo, "DROP TABLE base_artifacts", [])
    assert :ok = Bilimbi.Base.Artifacts.SchemaContract.verify_invariants(Repo, prefix: prefix)
  end

  test "operator form discovers every editable artifact setting" do
    fields = Bilimbi.Base.Settings.Form.fields(["operator"], nil)

    assert Enum.sort(Enum.map(fields, & &1.key)) ==
             ~w(artifacts.max_bytes artifacts.purge_batch_size artifacts.retention_days artifacts.storage_root)
  end

  test "rechecks access on every read, audits it, and exposes no private location", c do
    assert {:ok, document} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "sensitive", "text/plain")

    refute Map.has_key?(document, :storage_root)

    assert {:ok, %{bytes: "sensitive", metadata: ^document}} =
             Artifacts.read(c.scope, 51, TestOwner, document.id)

    assert_received {:authorized, :read, 51, _}
    Process.put({:deny, :read}, true)
    assert {:error, :forbidden} = Artifacts.read(c.scope, 51, TestOwner, document.id)
    assert_received {:authorized, :read, 51, _}
    {:ok, actions} = Audit.list_actions(c.scope)
    assert [action] = Enum.filter(actions, &(&1.event == "artifacts.read"))
    assert action.company_id == 51
    assert action.payload == %{"artifact_id" => document.id, "owner_id" => "test/documents"}
    assert {:ok, %{mode: mode}} = File.stat(Path.join(c.root, document.id))
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "refuses a second company in the same tenant, another tenant, and a substituted adapter",
       c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "private", "text/plain")
    {:ok, other_scope} = Tenancy.scope(42)

    for {scope, company, owner} <- [
          {c.scope, 52, TestOwner},
          {other_scope, 51, TestOwner},
          {c.scope, 51, Bilimbi.Base.Artifacts.OtherTestOwner}
        ] do
      assert {:error, :not_found} = Artifacts.read(scope, company, owner, doc.id)
      assert {:error, :not_found} = Artifacts.delete(scope, company, owner, doc.id)
    end

    assert {:error, :forbidden} =
             Artifacts.put(other_scope, 51, TestOwner, c.ref, "private", "text/plain")

    assert {:ok, _} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
  end

  test "expiry refuses reads before pruning, purge stays scoped and records delete and purge",
       c do
    {:ok, expired} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "old", "text/plain")
    {:ok, other_company} = Artifacts.put(c.scope, 52, TestOwner, c.ref, "other", "text/plain")

    for id <- [expired.id, other_company.id] do
      Repo.get!(Schema, id)
      |> change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()
    end

    assert {:error, :not_found} = Artifacts.read(c.scope, 51, TestOwner, expired.id)
    assert {:ok, %{deleted: [id], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    assert id == expired.id
    refute File.exists?(Path.join(c.root, id))
    assert File.exists?(Path.join(c.root, other_company.id))
    {:ok, actions} = Audit.list_actions(c.scope)
    assert Enum.count(actions, &(&1.event == "artifacts.delete")) == 1
    assert Enum.count(actions, &(&1.event == "artifacts.purge")) == 1
    assert {:ok, %{deleted: [], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
  end

  test "retention uses operator settings at creation and purge rechecks deletion authority", c do
    Settings.put("artifacts.retention_days", 2)
    before = DateTime.utc_now()
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    assert DateTime.diff(doc.expires_at, before, :second) in 172_800..172_801
    Repo.get!(Schema, doc.id) |> change(expires_at: before) |> Repo.update!()
    Process.put({:deny, :delete}, true)

    assert {:ok, %{deleted: [], errors: [{id, :forbidden}]}} =
             Artifacts.purge_expired(c.scope, 51, TestOwner)

    assert id == doc.id
    assert File.exists?(Path.join(c.root, doc.id))
  end

  test "missing retention, unsafe storage and configured upload size refuse writes", c do
    Settings.delete("artifacts.retention_days")

    assert {:error, :retention_not_configured} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    Settings.put("artifacts.retention_days", 30)
    File.chmod!(c.root, 0o755)

    assert {:error, :unsafe_storage_root} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    File.chmod!(c.root, 0o700)
    Settings.put("artifacts.max_bytes", 2)

    assert {:error, :invalid_size} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert Repo.aggregate(Schema, :count) == 0
  end

  test "PDF rendering follows authorization and stores through the shared seam", c do
    Process.put({:deny, :create}, true)
    assert {:error, :forbidden} = Artifacts.generate_pdf(c.scope, 51, TestOwner, c.ref, %{})
    refute_received :rendered
    Process.put({:deny, :create}, false)

    assert {:error, :invalid_pdf} =
             Artifacts.generate_pdf(c.scope, 51, TestOwner, c.ref, %{pdf: "invalid"})

    assert {:ok, doc} = Artifacts.generate_pdf(c.scope, 51, TestOwner, c.ref, %{})
    assert doc.content_type == "application/pdf"
    assert {:ok, %{bytes: "%PDF-1.7
%%EOF"}} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
  end

  test "storage-root changes preserve existing reads and cleanup location; bytes fail integrity",
       c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "original", "text/plain")
    Settings.put("artifacts.storage_root", "/unconfigured-new-root")
    assert {:ok, _} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    File.write!(Path.join(c.root, doc.id), "tampered")
    assert {:error, :integrity_failure} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    assert {:ok, :deleted} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
    refute File.exists?(Path.join(c.root, doc.id))
    assert {:error, :not_found} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
  end

  test "failed physical cleanup stays denied and can be retried", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    File.chmod!(c.root, 0o755)
    assert {:error, :unsafe_storage_root} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
    assert {:error, :not_found} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    File.chmod!(c.root, 0o700)
    assert {:ok, %{deleted: [id], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    assert id == doc.id
  end

  test "a sealed user actor cannot cross companies and read actions name that actor", c do
    user_scope = Bilimbi.Base.Tenancy.Authentication.sign_in(c.scope, 71, 51)
    {:ok, doc} = Artifacts.put(user_scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert {:error, :forbidden} =
             Artifacts.put(user_scope, 52, TestOwner, c.ref, "bytes", "text/plain")

    assert {:error, :forbidden} = Artifacts.read(user_scope, 52, TestOwner, doc.id)
    assert {:error, :forbidden} = Artifacts.delete(user_scope, 52, TestOwner, doc.id)
    assert {:error, :forbidden} = Artifacts.purge_expired(user_scope, 52, TestOwner)
    assert {:ok, _} = Artifacts.read(user_scope, 51, TestOwner, doc.id)
    {:ok, actions} = Audit.list_actions(c.scope)
    assert [action] = Enum.filter(actions, &(&1.event == "artifacts.read"))
    assert action.actor_type == "user"
    assert action.actor_id == 71
  end

  test "retention refuses unauthorized company maintenance before listing candidates", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    Repo.get!(Schema, doc.id) |> change(expires_at: DateTime.utc_now()) |> Repo.update!()
    Process.put({:deny, :purge}, true)
    assert {:error, :forbidden} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    refute_received {:authorized, :delete, _, _}
    assert File.exists?(Path.join(c.root, doc.id))
  end

  test "an unavailable action audit prevents bytes and deletion from being released", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    Ecto.Adapters.SQL.query!(Repo, "DROP TABLE base_audit_actions", [])
    assert {:error, :audit_unavailable} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    assert {:error, :audit_unavailable} = Artifacts.delete(c.scope, 51, TestOwner, doc.id)
    assert File.exists?(Path.join(c.root, doc.id))
    assert is_nil(Repo.get!(Schema, doc.id).deleted_at)
  end

  test "interrupted upload reservations stay inaccessible and expire with tracked bytes", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")
    row = Repo.get!(Schema, doc.id)
    row |> change(ready_at: nil) |> Repo.update!()
    assert {:error, :not_found} = Artifacts.read(c.scope, 51, TestOwner, doc.id)
    row |> change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second)) |> Repo.update!()
    assert {:ok, %{deleted: [id], errors: []}} = Artifacts.purge_expired(c.scope, 51, TestOwner)
    assert id == doc.id
    refute File.exists?(Path.join(c.root, doc.id))
  end

  test "public roots and symlinks cannot be selected for private uploads", c do
    public = Path.join(c.root, "public")
    File.mkdir!(public)
    File.chmod!(public, 0o700)
    Settings.put("artifacts.storage_root", public)

    assert {:error, :unsafe_storage_root} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    link = Path.join(c.root, "linked")
    File.ln_s!(public, link)
    Settings.put("artifacts.storage_root", link)

    assert {:error, :unsafe_storage_root} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert File.ls!(public) == []
  end

  test "artifact operations refuse an outer transaction", c do
    assert_raise ArgumentError, ~r/committed filesystem boundary/, fn ->
      Repo.transact(fn -> Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain") end)
    end

    assert Repo.aggregate(Schema, :count) == 0
  end

  test "revoked publication authority cleans the tracked file without making it readable", c do
    Process.put(:deny_create_after, 2)

    assert {:error, :forbidden} =
             Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert [row] = Repo.all(Schema)
    assert is_nil(row.ready_at)
    assert row.deleted_at
    assert row.purged_at
    assert File.ls!(c.root) == []
  end

  test "database refuses an invalid company and a missing tenant", c do
    {:ok, doc} = Artifacts.put(c.scope, 51, TestOwner, c.ref, "bytes", "text/plain")

    assert_raise Ecto.ConstraintError, fn ->
      Repo.get!(Schema, doc.id) |> change(company_id: 0) |> Repo.update!(mode: :savepoint)
    end

    assert_raise Ecto.ConstraintError, fn ->
      Repo.get!(Schema, doc.id) |> change(tenant_id: 999) |> Repo.update!(mode: :savepoint)
    end
  end
end
