defmodule Bilimbi.Base.MediaTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.{Media, Settings, Tenancy}
  alias Bilimbi.Base.Media.{AssetSchema, AttachmentSchema, SchemaContract, Storage}
  import Bilimbi.Base.Media.TestFixtures
  @secret "media-test-secret-0123456789012345678901234567890123456789"

  setup do
    install_registry!()
    on_exit(&Bilimbi.Base.ModuleRegistry.ContributionRegistry.clear_for_test!/0)
    Bilimbi.Base.Tenancy.TestFixtures.create_tenants_table!()
    Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!(%{id: 41})
    Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    Bilimbi.Base.Settings.TestFixtures.create_settings_table!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    create_media_tables!()
    root = Path.join(System.tmp_dir!(), "bilimbi-media-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    Settings.put("media.disks", %{"local" => root})
    {:ok, system} = Tenancy.scope(41)
    scope = Bilimbi.Base.Tenancy.Authentication.sign_in(system, 91, 73)
    other_user = Bilimbi.Base.Tenancy.Authentication.sign_in(system, 92, 73)
    {:ok, other_tenant} = Tenancy.scope(42)

    %{
      scope: scope,
      other_user: other_user,
      other_tenant: other_tenant,
      system: system,
      root: root,
      upload: upload_file!(root)
    }
  end

  test "verifies the independent Laravel schema and operator settings" do
    assert :ok =
             Bilimbi.Base.Database.SchemaVerifier.verify(Repo, SchemaContract.tables(),
               prefix: temporary_schema!()
             )

    fields = Bilimbi.Base.Settings.Form.fields(["operator"], nil)

    assert Enum.sort(Enum.map(fields, & &1.key)) ==
             ~w(media.attachment_allowed_types media.attachment_disk media.disks media.max_bytes media.stream_ttl_seconds)
  end

  test "uploads an original using detected MIME and a tenant-prefixed generated key", c do
    assert {:ok, asset} =
             Media.put_upload(c.scope, "local", "photos", c.upload, %{"caption" => "photo"})

    assert asset.kind == "original"
    assert asset.mime_type == "text/plain"
    assert asset.metadata == %{"caption" => "photo"}
    refute Map.has_key?(asset, :storage_key)
    row = Repo.get!(AssetSchema, asset.id)
    assert String.starts_with?(row.storage_key, "tenants/41/photos/")
    assert {:ok, "attachment contents"} = Storage.read("local", row.storage_key)
  end

  test "registers legacy original and nested derivatives and recursively deletes bytes", c do
    File.write!(Path.join(c.root, "legacy.jpg"), "legacy")

    assert {:ok, original} =
             Media.store_original("local", "legacy.jpg", %{
               original_filename: "original.jpg",
               mime_type: "image/jpeg"
             })

    assert {:ok, child} =
             Media.put_derivative_bytes(
               original.id,
               "thumbnail",
               "local",
               "thumb.png",
               "thumb",
               %{mime_type: "image/png"}
             )

    assert {:ok, nested} =
             Media.put_derivative_bytes(child.id, "small", "local", "small.png", "small")

    assert [^child] = Media.list_derivatives(original.id)

    assert {:error, :invalid_derivative_kind} =
             Media.store_derivative(original.id, "original", "local", "bad", %{})

    assert {:ok, :deleted} = Media.delete_asset(original.id)

    for asset <- [original, child, nested],
        do: assert(Media.get_asset(asset.id) == {:error, :not_found})

    for file <- ~w(legacy.jpg thumb.png small.png),
        do: refute(File.exists?(Path.join(c.root, file)))
  end

  test "supports safe external display URLs without attempting to stream bytes" do
    {:ok, asset} =
      Media.store_original("external", "external-1", %{
        metadata: %{"public_url" => "https://example.test/image.jpg"}
      })

    assert {:ok, "https://example.test/image.jpg"} = Media.display_url(asset.id, @secret)
    assert {:error, :source_not_stored} = Media.stream_url(asset.id, @secret)

    {:ok, bad} =
      Media.store_original("external", "external-2", %{
        metadata: %{"public_url" => "javascript:alert(1)"}
      })

    assert {:error, :invalid_external_url} = Media.display_url(bad.id, @secret)
  end

  test "signed stream links bind asset ID and expire", c do
    {:ok, asset} = Media.put_upload(c.scope, "local", "photos", c.upload)
    {:ok, url} = Media.stream_url(asset.id, @secret)
    token = URI.decode_query(URI.parse(url).query)["token"]

    assert {:ok, %{bytes: "attachment contents"}} =
             Media.read_signed_asset(asset.id, token, @secret)

    assert {:error, :invalid} = Media.read_signed_asset(asset.id + 1, token, @secret)
    assert {:error, :invalid} = Media.read_signed_asset(asset.id, token <> "x", @secret)

    expired =
      Phoenix.Token.sign(@secret, "base/media-asset", asset.id,
        max_age: 1,
        signed_at: System.system_time(:second) - 20
      )

    assert {:error, :expired} = Media.read_signed_asset(asset.id, expired, @secret)
  end

  test "uploads drafts with compatible ULIDs and immutable submitted evidence", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    assert draft.public_id =~ ~r/\A[0-7][0-9A-HJKMNP-TV-Z]{25}\z/
    assert {draft.state, draft.uploaded_by_type, draft.uploaded_by_id} == {"draft", "user", 91}
    refute Map.has_key?(draft, :media_asset_id)

    assert {:ok, [submitted]} =
             Media.submit_attachments(c.scope, {"test.record", "1"}, [
               draft.public_id,
               draft.public_id
             ])

    assert submitted.state == "submitted"
    assert submitted.submitted_at

    assert {:ok, [^submitted]} =
             Media.submit_attachments(c.scope, {"test.record", "1"}, [draft.public_id])

    assert {:ok, [^submitted]} =
             Media.retain_drafts(c.scope, {"test.record", "1"}, [draft.public_id])

    assert {:error, :immutable_attachment} = Media.discard_draft(c.scope, draft.public_id)

    assert {:ok, %{bytes: "attachment contents"}} =
             Media.download_attachment(c.scope, draft.public_id)
  end

  test "rechecks subject permissions and missing subjects; unknown policy fails closed", c do
    assert {:error, :unregistered_subject} =
             Media.upload_attachment(c.scope, {"unknown.record", "1"}, c.upload)

    assert {:error, :subject_not_found} =
             Media.upload_attachment(c.scope, {"test.record", "missing"}, c.upload)

    Process.put({:deny_media, :upload}, true)
    assert {:error, :forbidden} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    assert Repo.aggregate(AssetSchema, :count) == 0
    Process.delete({:deny_media, :upload})
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    Process.put({:deny_media, :download}, true)
    assert {:error, :forbidden} = Media.download_attachment(c.scope, draft.public_id)
    Process.put({:deny_media, :submit}, true)

    assert {:error, :forbidden} =
             Media.submit_attachments(c.scope, {"test.record", "1"}, [draft.public_id])

    assert {:error, :forbidden} =
             Media.retain_drafts(c.scope, {"test.record", "1"}, [draft.public_id])

    assert Repo.get_by!(AttachmentSchema, public_id: draft.public_id).state == "draft"
  end

  test "retains the exact adopted legacy subject alias", c do
    alias_type = "App\\Domain\\Test\\Record"
    {:ok, draft} = Media.upload_attachment(c.scope, {alias_type, "1"}, c.upload)
    assert draft.subject_type == alias_type
    assert {:ok, [_]} = Media.submit_attachments(c.scope, {alias_type, "1"}, [draft.public_id])
    assert {:ok, _} = Media.download_attachment(c.scope, draft.public_id)
  end

  test "submit and retain refuse unavailable and wrong-subject references atomically", c do
    {:ok, first} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    {:ok, second} = Media.upload_attachment(c.scope, {"test.record", "2"}, c.upload)

    assert {:error, :wrong_subject} =
             Media.submit_attachments(c.scope, {"test.record", "1"}, [
               first.public_id,
               second.public_id
             ])

    assert {:error, :attachments_unavailable} =
             Media.retain_drafts(c.scope, {"test.record", "1"}, [first.public_id, "unavailable"])

    assert Enum.all?(
             Repo.all(AttachmentSchema),
             &(&1.state == "draft" and is_nil(&1.retained_at))
           )

    other = Bilimbi.Base.Tenancy.Authentication.sign_in(c.other_tenant, 91, 73)

    assert {:error, :attachments_unavailable} =
             Media.submit_attachments(other, {"test.record", "1"}, [first.public_id])

    assert {:error, :not_found} = Media.download_attachment(other, first.public_id)
    assert {:error, :not_found} = Media.discard_draft(other, first.public_id)
  end

  test "only uploader may discard and cleanup remains tenant-scoped", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
    asset = Repo.get!(AssetSchema, row.media_asset_id)
    assert {:error, :not_uploader} = Media.discard_draft(c.other_user, draft.public_id)

    assert {:ok, 0} =
             Media.cleanup_drafts_before(
               c.other_tenant,
               NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
             )

    assert {:ok, :deleted} = Media.discard_draft(c.scope, draft.public_id)
    refute File.exists?(Path.join(c.root, asset.storage_key))
    assert Repo.get(AttachmentSchema, row.id) == nil
    assert Repo.get(AssetSchema, asset.id) == nil
  end

  test "retained, submitted and recent drafts survive abandoned draft cleanup", c do
    drafts =
      for _ <- 1..4 do
        {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
        draft
      end

    [abandoned, retained, submitted, recent] = drafts
    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -172_800) |> NaiveDateTime.truncate(:second)

    for draft <- [abandoned, retained, submitted],
        do:
          Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
          |> change(created_at: old)
          |> Repo.update!()

    assert {:ok, [_]} = Media.retain_drafts(c.scope, {"test.record", "1"}, [retained.public_id])

    assert {:ok, [_]} =
             Media.submit_attachments(c.scope, {"test.record", "1"}, [submitted.public_id])

    assert {:ok, 1} =
             Media.cleanup_drafts_before(
               c.system,
               NaiveDateTime.add(NaiveDateTime.utc_now(), -86_400)
             )

    assert Repo.get_by(AttachmentSchema, public_id: abandoned.public_id) == nil

    for draft <- [retained, submitted, recent],
        do: assert(Repo.get_by(AttachmentSchema, public_id: draft.public_id))
  end

  test "generic links, derivatives and deletion cannot bypass private attachment policies", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    asset_id = Repo.get_by!(AttachmentSchema, public_id: draft.public_id).media_asset_id
    token = Phoenix.Token.sign(@secret, "base/media-asset", asset_id)
    assert {:error, :private_attachment} = Media.stream_url(asset_id, @secret)
    assert {:error, :private_attachment} = Media.read_signed_asset(asset_id, token, @secret)
    assert {:error, :private_attachment} = Media.delete_asset(asset_id)

    assert {:error, :private_attachment} =
             Media.store_derivative(asset_id, "thumb", "local", "thumb")
  end

  test "system and impersonated actors cannot become an evidence uploader", c do
    assert {:error, :user_required} =
             Media.upload_attachment(c.system, {"test.record", "1"}, c.upload)

    impersonated =
      Bilimbi.Base.Tenancy.Authentication.sign_in(c.system, 91, 73,
        impersonator_id: 99,
        impersonation_session_id: "session-1"
      )

    assert {:error, :user_required} =
             Media.upload_attachment(impersonated, {"test.record", "1"}, c.upload)

    assert_raise FunctionClauseError, fn ->
      Media.upload_attachment(
        Bilimbi.Base.Database.TestHelpers.opaque(41),
        {"test.record", "1"},
        c.upload
      )
    end
  end

  test "refuses forged active MIME, empty uploads, oversized files and disallowed attachment types",
       c do
    html = upload_file!(c.root, "<!DOCTYPE html><html><body>active</body></html>", "image.png")
    html = %{html | content_type: "image/png"}
    assert {:error, :disallowed_type} = Media.put_upload(c.scope, "local", "uploads", html)

    assert {:error, :disallowed_type} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, html)

    empty = upload_file!(c.root, "")
    assert {:error, :invalid_size} = Media.upload_attachment(c.scope, {"test.record", "1"}, empty)
    Settings.put("media.max_bytes", 1)
    assert {:error, :invalid_size} = Media.put_upload(c.scope, "local", "photos", c.upload)
    Settings.put("media.max_bytes", 10_485_760)
    Settings.put("media.attachment_allowed_types", ["application/pdf"])

    assert {:error, :disallowed_type} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
  end

  test "unsafe keys, roots and symlinks refuse reads and writes", c do
    for key <- ["../outside", "/tmp/outside", "a/../b", "a//b", "a\\b", "a/./b"],
        do: assert(Media.store_original("local", key) == {:error, :unsafe_storage_key})

    link = Path.join(c.root, "link")
    File.ln_s!(System.tmp_dir!(), link)
    assert {:error, :unsafe_storage_key} = Storage.write("local", "link/outside", "bytes")
    File.chmod!(c.root, 0o755)
    assert {:error, :unsafe_storage_root} = Media.put_upload(c.scope, "local", "photos", c.upload)
    File.chmod!(c.root, 0o700)
    public = Path.join(c.root, "public")
    File.mkdir!(public)
    File.chmod!(public, 0o700)
    Settings.put("media.disks", %{"local" => public})
    assert {:error, :unsafe_storage_root} = Media.put_upload(c.scope, "local", "photos", c.upload)
  end

  test "failed derivative registration removes newly written bytes and refuses overwrite", c do
    {:ok, original} = Media.store_original("local", "legacy")

    assert {:error, :invalid_derivative_kind} =
             Media.put_derivative_bytes(original.id, "original", "local", "bad", "bytes")

    refute File.exists?(Path.join(c.root, "bad"))
    assert {:ok, _} = Media.put_derivative_bytes(original.id, "thumb", "local", "same", "first")

    assert {:error, :storage_key_exists} =
             Media.put_derivative_bytes(original.id, "thumb", "local", "same", "second")

    assert File.read!(Path.join(c.root, "same")) == "first"
  end

  test "database enforces unique references and restricted asset deletion", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
    asset = Repo.get!(AssetSchema, row.media_asset_id)
    assert_raise Ecto.ConstraintError, fn -> Repo.delete!(asset, mode: :savepoint) end
    assert_raise Ecto.ConstraintError, fn -> Repo.insert!(%{row | id: nil}, mode: :savepoint) end

    assert_raise Ecto.ConstraintError, fn ->
      Repo.update!(change(row, tenant_id: 999), mode: :savepoint)
    end
  end

  test "filesystem APIs refuse an outer transaction while submission rolls back with business work",
       c do
    assert_raise ArgumentError, ~r/committed filesystem boundary/, fn ->
      Repo.transact(fn -> Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload) end)
    end

    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)

    assert {:error, :business_refused} =
             Repo.transact(fn ->
               {:ok, [_]} =
                 Media.submit_attachments(c.scope, {"test.record", "1"}, [draft.public_id])

               {:error, :business_refused}
             end)

    assert Repo.get_by!(AttachmentSchema, public_id: draft.public_id).state == "draft"
  end

  test "failed draft publication removes bytes and leaves no binding", c do
    too_long = %{c.upload | filename: String.duplicate("a", 256)}
    before = File.ls!(c.root)

    assert {:error, %Ecto.Changeset{}} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, too_long)

    assert Repo.aggregate(AttachmentSchema, :count) == 0
    assert Repo.aggregate(AssetSchema, :count) == 0
    # Only empty tenant directories may remain after the failed publication.
    assert Path.wildcard(Path.join(c.root, "tenants/**/*")) |> Enum.all?(&File.dir?/1)
    assert Enum.all?(before, &File.exists?(Path.join(c.root, &1)))
  end

  test "captured mutations retain Laravel record identity and the sealed performing user", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    {:ok, [_]} = Media.submit_attachments(c.scope, {"test.record", "1"}, [draft.public_id])
    {:ok, mutations} = Bilimbi.Base.Audit.list_mutations(c.system)

    attachment =
      Enum.filter(mutations, &(&1.auditable_type == "App\\Base\\Media\\Models\\MediaAttachment"))

    assert Enum.sort(Enum.map(attachment, & &1.event)) == ["created", "updated"]

    assert Enum.all?(
             attachment,
             &(&1.actor_type == "user" and &1.actor_id == 91 and &1.tenant_id == 41)
           )

    assert Enum.any?(
             mutations,
             &(&1.auditable_type == "App\\Base\\Media\\Models\\MediaAsset" and &1.actor_id == 91)
           )
  end

  test "plain system cleanup is recorded as console, not a guest", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)

    assert {:ok, 1} =
             Media.cleanup_drafts_before(
               c.system,
               NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
             )

    {:ok, mutations} = Bilimbi.Base.Audit.list_mutations(c.system)

    deletes =
      Enum.filter(
        mutations,
        &(&1.event == "deleted" and
            &1.auditable_type == "App\\Base\\Media\\Models\\MediaAttachment" and
            &1.auditable_id == to_string(row.id))
      )

    assert [_ | _] = deletes
    assert Enum.all?(deletes, &(&1.actor_type == "console" and &1.actor_id == 0))
  end

  test "deleting a file whose directory is already gone counts as absent", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
    asset = Repo.get!(AssetSchema, row.media_asset_id)
    File.rm_rf!(Path.join(c.root, Path.dirname(asset.storage_key)))

    assert {:ok, :deleted} = Media.discard_draft(c.scope, draft.public_id)
    assert Repo.get(AttachmentSchema, row.id) == nil

    File.ln_s!(System.tmp_dir!(), Path.join(c.root, "linked"))
    assert {:error, :unsafe_storage_key} = Storage.delete("local", "linked/file")
  end

  test "failed file cleanup reports failure after removing the draft reference", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
    asset = Repo.get!(AssetSchema, row.media_asset_id)
    File.chmod!(c.root, 0o755)
    assert {:error, :cleanup_failed} = Media.discard_draft(c.scope, draft.public_id)
    assert Repo.get(AttachmentSchema, row.id) == nil
    assert Repo.get(AssetSchema, asset.id) == nil
    assert File.exists?(Path.join(c.root, asset.storage_key))
    assert {:error, :not_found} = Media.download_attachment(c.scope, draft.public_id)
  end

  test "subject upload rules may narrow file types and size within operator limits", c do
    assert {:error, :invalid_size} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload, %{max_bytes: 1})

    assert {:error, :disallowed_type} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload, %{
               allowed_mime_types: ["application/pdf"]
             })

    assert {:error, :invalid_rules} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload, %{max_bytes: 0})

    assert {:ok, _} =
             Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload, %{
               allowed_mime_types: ["text/plain"]
             })
  end

  test "adopted metadata arrays keep their JSON shape and invalid external URLs fail clearly" do
    assert {:ok, asset} =
             Media.store_original("external", "array-metadata", %{
               metadata: ["tag", %{"nested" => []}]
             })

    assert {:ok, %{metadata: ["tag", %{"nested" => []}]}} = Media.get_asset(asset.id)
    assert {:error, :invalid_external_url} = Media.display_url(asset.id, @secret)
  end
end
