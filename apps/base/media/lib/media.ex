defmodule Bilimbi.Base.Media do
  @moduledoc """
  Shared compatible media assets and private subject attachments.

  Asset registration/byte APIs are for trusted owning adapters, which authorize
  their own workflow before calling. Assets have no tenant column in Belimbing;
  new uploaded keys are tenant-prefixed. Private attachments always take a scope
  and recheck their subject's registered policy. Submitted references have no
  mutation/deletion API. Generic asset links and deletion refuse private bindings.

  Use this facade instead of hand-rolled upload storage or attachment downloads.
  Generated private PDFs use `Bilimbi.Base.Artifacts.generate_pdf/5` and its PDF
  adapter, rather than a second PDF engine. See docs/README.md.

  Filesystem operations must run outside a caller transaction. Submit/retain
  can join a business transaction. Like Belimbing, row deletion commits before
  removing files; filesystem failures are reported as `:cleanup_failed`.
  """
  alias Bilimbi.Base.Media.{AssetStore, Attribution, PrivateAttachmentStore, Storage, Upload}
  alias Bilimbi.Base.{Repo, Settings}
  alias Bilimbi.Base.Tenancy.Scope

  use Phoenix.VerifiedRoutes,
    router: Bilimbi.Base.UI.RouteContract,
    endpoint: Bilimbi.Base.UI.ScriptPath

  def store_original(disk, key, attrs \\ %{}),
    do: summarize(AssetStore.original(disk, key, attrs))

  def store_derivative(parent_id, kind, disk, key, attrs \\ %{}),
    do: summarize(AssetStore.derivative(parent_id, kind, disk, key, attrs))

  def get_asset(id), do: summarize(AssetStore.fetch(id))
  def list_derivatives(id), do: Enum.map(AssetStore.children(id), &AssetStore.summary/1)

  def put_upload(%Scope{} = scope, disk, directory, file, metadata \\ nil) do
    filesystem_boundary!()

    with :ok <- Storage.validate_key(directory),
         {:ok, bytes, attrs} <- Upload.read(file) do
      key = "tenants/#{Scope.tenant_id(scope)}/#{directory}/#{Ecto.UUID.generate()}"

      Attribution.run(scope, fn ->
        AssetStore.put(
          disk,
          key,
          bytes,
          Map.put(attrs, :metadata, metadata),
          &AssetStore.original(disk, key, &1)
        )
      end)
      |> summarize()
    end
  end

  def put_derivative_bytes(parent_id, kind, disk, key, bytes, attrs \\ %{})
      when is_binary(bytes) do
    filesystem_boundary!()

    with {:ok, _} <- AssetStore.fetch(parent_id),
         :ok <- AssetStore.public_tree(parent_id),
         :ok <- Upload.allowed(Map.get(attrs, :mime_type), false) do
      AssetStore.put(
        disk,
        key,
        bytes,
        attrs,
        &AssetStore.derivative(parent_id, kind, disk, key, &1)
      )
      |> summarize()
    end
  end

  def delete_asset(id) do
    filesystem_boundary!()
    AssetStore.delete(id)
  end

  def display_url(id, signing_context) do
    with {:ok, asset} <- AssetStore.fetch(id), :ok <- AssetStore.public_tree(id) do
      if asset.disk == "external" do
        url = if is_map(asset.metadata), do: Map.get(asset.metadata, "public_url")
        uri = if is_binary(url), do: URI.parse(url)

        if uri && String.downcase(uri.scheme || "") in ["http", "https"] && is_binary(uri.host) &&
             uri.host != "", do: {:ok, url}, else: {:error, :invalid_external_url}
      else
        stream_url(id, signing_context)
      end
    end
  end

  def stream_url(id, signing_context) do
    with {:ok, asset} <- AssetStore.fetch(id),
         :ok <- AssetStore.public_tree(id),
         false <- asset.disk == "external" do
      token =
        Phoenix.Token.sign(signing_context, "base/media-asset", id,
          max_age: Settings.get("media.stream_ttl_seconds")
        )

      {:ok, ~p"/media/assets/#{id}/stream?#{[token: token]}"}
    else
      true -> {:error, :source_not_stored}
      error -> error
    end
  end

  def read_signed_asset(id, token, signing_context) do
    with {:ok, ^id} <- Phoenix.Token.verify(signing_context, "base/media-asset", token),
         {:ok, asset} <- AssetStore.fetch(id),
         :ok <- AssetStore.public_tree(id),
         {:ok, bytes} <- Storage.read(asset.disk, asset.storage_key) do
      {:ok,
       %{
         bytes: bytes,
         filename: asset.original_filename || Path.basename(asset.storage_key),
         mime_type: asset.mime_type
       }}
    else
      {:ok, _other} -> {:error, :invalid}
      error -> error
    end
  end

  def upload_attachment(%Scope{} = scope, subject, file, rules \\ %{}) do
    filesystem_boundary!()
    PrivateAttachmentStore.upload(scope, subject, file, rules)
  end

  def submit_attachments(%Scope{} = scope, subject, ids),
    do: PrivateAttachmentStore.submit(scope, subject, ids)

  def retain_drafts(%Scope{} = scope, subject, ids),
    do: PrivateAttachmentStore.retain(scope, subject, ids)

  def download_attachment(%Scope{} = scope, public_id),
    do: PrivateAttachmentStore.download(scope, public_id)

  def discard_draft(%Scope{} = scope, public_id) do
    filesystem_boundary!()
    PrivateAttachmentStore.discard(scope, public_id)
  end

  def cleanup_drafts_before(%Scope{} = scope, %NaiveDateTime{} = cutoff) do
    filesystem_boundary!()
    PrivateAttachmentStore.cleanup(scope, cutoff)
  end

  defp summarize({:ok, row}), do: {:ok, AssetStore.summary(row)}
  defp summarize(error), do: error

  defp filesystem_boundary! do
    if Repo.in_transaction?(),
      do:
        raise(
          ArgumentError,
          "Media filesystem operations require a committed filesystem boundary"
        )
  end
end
