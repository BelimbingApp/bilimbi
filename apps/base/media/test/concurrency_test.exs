defmodule Bilimbi.Base.Media.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Bilimbi.Base.Database.LockSchema
  import Bilimbi.Base.Media.TestFixtures
  alias Bilimbi.Base.{Media, Repo, Settings}
  alias Bilimbi.Base.Media.AttachmentSchema
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures

  setup do
    schema = create!("media_lock")
    install_registry!()
    on_exit(&Bilimbi.Base.ModuleRegistry.ContributionRegistry.clear_for_test!/0)
    root = Path.join(System.tmp_dir!(), "bilimbi-media-lock-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    on_schema!(schema, fn ->
      TenancyFixtures.create_tenants_table!(persistent: true)
      TenancyFixtures.insert_tenant!(%{id: 41})
      # Owner fixtures alone define the tables. Settings stay connection-local;
      # contenders consume the cached storage configuration below.
      Bilimbi.Base.Settings.TestFixtures.create_settings_table!()
      Bilimbi.Base.Audit.TestFixtures.create_audit_tables!(persistent: true)
      create_media_tables!(schema)
      Settings.put("media.disks", %{"local" => root})
      Settings.get("media.max_bytes")
      Settings.get("media.attachment_allowed_types")
      Settings.get("media.attachment_disk")
    end)

    scope = Bilimbi.Base.Tenancy.Authentication.sign_in(TenancyFixtures.scope(41), 91, 73)
    %{schema: schema, scope: scope, root: root}
  end

  test "discard waits for submission then refuses the freshly submitted evidence", c do
    on_schema!(c.schema, fn ->
      {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, upload_file!(c.root))
      row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
      parent = self()
      supervisor = start_supervised!(Task.Supervisor)

      holder =
        Task.Supervisor.async_nolink(supervisor, fn ->
          checkout_on_schema!(c.schema, fn ->
            Repo.transact(fn ->
              {:ok, result} =
                Media.submit_attachments(c.scope, {"test.record", "1"}, [draft.public_id])

              send(parent, :submitted_locked)
              await_message!(:commit)
              {:ok, result}
            end)
          end)
        end)

      assert_receive :submitted_locked, 5_000

      contender =
        Task.Supervisor.async_nolink(supervisor, fn ->
          checkout_on_schema!(c.schema, fn ->
            send(parent, {:contender_backend, backend_pid!()})
            Media.discard_draft(c.scope, draft.public_id)
          end)
        end)

      assert_receive {:contender_backend, pid}, 5_000
      await_row_lock!(pid)
      send(holder.pid, :commit)
      assert {:ok, [_]} = Task.await(holder, 10_000)
      assert {:error, :immutable_attachment} = Task.await(contender, 10_000)
      assert Repo.get!(AttachmentSchema, row.id).state == "submitted"

      assert {:ok, %{bytes: "attachment contents"}} =
               Media.download_attachment(c.scope, draft.public_id)
    end)
  end

  test "cleanup rechecks retention after waiting for a competing retain operation", c do
    on_schema!(c.schema, fn ->
      {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, upload_file!(c.root))
      cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
      parent = self()
      supervisor = start_supervised!(Task.Supervisor)

      holder =
        Task.Supervisor.async_nolink(supervisor, fn ->
          checkout_on_schema!(c.schema, fn ->
            Repo.transact(fn ->
              {:ok, rows} = Media.retain_drafts(c.scope, {"test.record", "1"}, [draft.public_id])
              send(parent, :retained_locked)
              await_message!(:commit)
              {:ok, rows}
            end)
          end)
        end)

      assert_receive :retained_locked, 5_000

      contender =
        Task.Supervisor.async_nolink(supervisor, fn ->
          checkout_on_schema!(c.schema, fn ->
            send(parent, {:contender_backend, backend_pid!()})
            Media.cleanup_drafts_before(TenancyFixtures.scope(41), cutoff)
          end)
        end)

      assert_receive {:contender_backend, pid}, 5_000
      await_row_lock!(pid)
      send(holder.pid, :commit)
      assert {:ok, [_]} = Task.await(holder, 10_000)
      assert {:ok, 0} = Task.await(contender, 10_000)
      assert Repo.get_by!(AttachmentSchema, public_id: draft.public_id).retained_at
    end)
  end
end
