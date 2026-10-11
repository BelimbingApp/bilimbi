defmodule Bilimbi.Base.Media.Web.MediaRoutesTest do
  use BilimbiWeb.ConnCase, async: false
  alias Bilimbi.Base.{Media, Settings, Tenancy}
  alias Bilimbi.Base.Media.{AssetSchema, AttachmentSchema, TestFixtures}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo

  setup do
    signed_in_identity!()
    TestFixtures.create_media_tables!()
    previous = ContributionRegistry.snapshot!()

    media =
      Bilimbi.Base.Media.ContributionValidator.validate_contributions!([TestFixtures.entry()])

    ContributionRegistry.put_consumers_for_test!(Map.put(previous.consumers, :media, media))
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(previous) end)
    root = Path.join(System.tmp_dir!(), "bilimbi-media-web-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    Settings.put("media.disks", %{"local" => root})
    {:ok, scope} = Tenancy.scope(41)
    scope = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 91, 73)
    upload = TestFixtures.upload_file!(root)
    %{root: root, scope: scope, upload: upload}
  end

  test "asset stream needs its own valid signature, supports inline raster and forces other types to download",
       c do
    {:ok, asset} = Media.put_upload(c.scope, "local", "photos", c.upload)
    assert get(c.conn, ~p"/media/assets/#{asset.id}/stream").status == 403
    {:ok, url} = Media.stream_url(asset.id, BilimbiWeb.Endpoint)
    conn = get(c.conn, url)
    assert response(conn, 200) == "attachment contents"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    assert hd(get_resp_header(conn, "content-disposition")) =~ "attachment;"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
    file = Path.join(c.root, "image.jpg")
    File.write!(file, "raster")

    {:ok, image} =
      Media.store_original("local", "image.jpg", %{
        mime_type: "image/jpeg",
        original_filename: "a\"\r\nX-Test: injected.jpg"
      })

    {:ok, url} = Media.stream_url(image.id, BilimbiWeb.Endpoint)
    conn = get(c.conn, url)
    assert response(conn, 200) == "raster"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert hd(get_resp_header(conn, "content-disposition")) =~ "inline;"
    refute hd(get_resp_header(conn, "content-disposition")) =~ "\r\n"
    assert get_resp_header(conn, "x-test") == []
  end

  test "private download authenticates and rechecks subject policy every time", c do
    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    path = ~p"/media/attachments/#{draft.public_id}"
    assert get(c.conn, path).status == 302
    conn = c.conn |> log_in_as() |> get(path)
    assert response(conn, 200) == "attachment contents"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    Process.put({:deny_media, :download}, true)
    assert c.conn |> log_in_as() |> get(path) |> response(403) == "Forbidden"
    Process.delete({:deny_media, :download})
    row = Repo.get_by!(AttachmentSchema, public_id: draft.public_id)
    asset = Repo.get!(AssetSchema, row.media_asset_id)
    File.rm!(Path.join(c.root, asset.storage_key))
    assert c.conn |> log_in_as() |> get(path) |> response(404) == "Not found"
  end

  test "unknown private references and absent files return 404; private assets cannot be signed",
       c do
    assert c.conn
           |> log_in_as()
           |> get(~p"/media/attachments/01ARZ3NDEKTSV4RRFFQ69G5FAV")
           |> response(404) == "Not found"

    {:ok, draft} = Media.upload_attachment(c.scope, {"test.record", "1"}, c.upload)
    id = Repo.get_by!(AttachmentSchema, public_id: draft.public_id).media_asset_id
    secret = Application.fetch_env!(:web, BilimbiWeb.Endpoint)[:secret_key_base]
    token = Phoenix.Token.sign(secret, "base/media-asset", id)
    assert get(c.conn, ~p"/media/assets/#{id}/stream?#{[token: token]}").status == 403
    {:ok, asset} = Media.store_original("local", "missing.jpg", %{mime_type: "image/jpeg"})
    {:ok, url} = Media.stream_url(asset.id, BilimbiWeb.Endpoint)
    assert get(c.conn, url).status == 404
  end
end
