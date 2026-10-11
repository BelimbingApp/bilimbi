defmodule Bilimbi.Base.Media.AssetStore do
  @moduledoc false
  import Ecto.Query
  alias Bilimbi.Base.Media.{AssetSchema, AttachmentSchema, Storage}
  alias Bilimbi.Base.Repo

  def fetch(id) when is_integer(id) and id > 0 do
    case Repo.get(AssetSchema, id) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  def fetch(_), do: {:error, :not_found}

  def original(disk, key, attrs) do
    with :ok <- registration(disk, key) do
      %AssetSchema{}
      |> AssetSchema.changeset(
        Map.merge(attributes(attrs), %{
          disk: disk,
          storage_key: key,
          kind: "original",
          parent_id: nil
        })
      )
      |> Repo.insert()
    end
  end

  def derivative(parent_id, kind, disk, key, attrs)
      when is_binary(kind) and kind != "original" and kind != "" do
    Repo.transact(fn ->
      with {:ok, _parent} <- lock(parent_id),
           :ok <- public_tree(parent_id),
           :ok <- registration(disk, key) do
        %AssetSchema{}
        |> AssetSchema.changeset(
          Map.merge(attributes(attrs), %{
            disk: disk,
            storage_key: key,
            kind: kind,
            parent_id: parent_id
          })
        )
        |> Repo.insert()
      end
    end)
  end

  def derivative(_parent, _kind, _disk, _key, _attrs), do: {:error, :invalid_derivative_kind}

  def put(disk, key, bytes, attrs, register) do
    with :ok <- Storage.write(disk, key, bytes) do
      try do
        case register.(Map.put(attrs, :file_size, byte_size(bytes))) do
          {:ok, row} ->
            {:ok, row}

          {:error, _} = error ->
            Storage.delete(disk, key)
            error
        end
      rescue
        error ->
          Storage.delete(disk, key)
          reraise error, __STACKTRACE__
      catch
        kind, reason ->
          Storage.delete(disk, key)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  def delete(id) do
    with {:ok, rows} <-
           Repo.transact(fn ->
             with {:ok, _} <- lock(id), :ok <- public_tree(id) do
               rows = locked_tree(id)
               Enum.each(Enum.reverse(rows), &Repo.delete!/1)
               {:ok, rows}
             end
           end) do
      cleanup(rows)
    end
  end

  # Only the attachment lifecycle calls this, inside the transaction which
  # first locks and removes a draft binding. FK RESTRICT protects submitted
  # evidence even when the asset is addressed through the generic asset API.
  def delete_draft_asset!(id) do
    {:ok, _} = lock(id)
    rows = locked_tree(id)
    Enum.each(Enum.reverse(rows), &Repo.delete!/1)
    rows
  end

  def cleanup(rows) do
    Enum.reduce_while(rows, {:ok, :deleted}, fn row, _acc ->
      case Storage.delete(row.disk, row.storage_key) do
        :ok -> {:cont, {:ok, :deleted}}
        {:error, _} -> {:halt, {:error, :cleanup_failed}}
      end
    end)
  end

  def children(id), do: Repo.all(from a in AssetSchema, where: a.parent_id == ^id, order_by: a.id)

  def public_tree(id) do
    ids = Enum.map(tree(id), & &1.id) ++ ancestor_ids(id)
    if private_binding?(ids), do: {:error, :private_attachment}, else: :ok
  end

  # Owner-local global invariant: the assets table has no tenant column and
  # a generic signed stream must refuse a private binding in ANY tenant.
  # A scoped miss here could expose an attachment's bytes.
  defp private_binding?(asset_ids),
    do: Repo.exists?(from a in AttachmentSchema, where: a.media_asset_id in ^asset_ids)

  def summary(row),
    do:
      Map.take(row, [
        :id,
        :parent_id,
        :kind,
        :original_filename,
        :mime_type,
        :file_size,
        :metadata,
        :created_at,
        :updated_at
      ])

  defp lock(id) do
    case Repo.one(from a in AssetSchema, where: a.id == ^id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  defp tree(id, visited \\ MapSet.new()) do
    if MapSet.member?(visited, id), do: raise(ArgumentError, "cyclic media asset tree")

    case fetch(id) do
      {:ok, row} -> [row | Enum.flat_map(children(id), &tree(&1.id, MapSet.put(visited, id)))]
      {:error, :not_found} -> []
    end
  end

  # Lock each parent before discovering its children. Derivative insertion
  # takes the same parent lock, so a concurrent nested derivative is either
  # included with its file or refused after deletion; DB cascade cannot hide it.
  defp locked_tree(id, visited \\ MapSet.new()) do
    if MapSet.member?(visited, id), do: raise(ArgumentError, "cyclic media asset tree")

    case lock(id) do
      {:ok, row} ->
        [row | Enum.flat_map(children(id), &locked_tree(&1.id, MapSet.put(visited, id)))]

      {:error, :not_found} ->
        []
    end
  end

  defp ancestor_ids(id, visited \\ MapSet.new()) do
    if MapSet.member?(visited, id), do: raise(ArgumentError, "cyclic media asset tree")

    case fetch(id) do
      {:ok, %{parent_id: parent}} when not is_nil(parent) ->
        [parent | ancestor_ids(parent, MapSet.put(visited, id))]

      _ ->
        []
    end
  end

  defp attributes(attrs),
    do: Map.take(attrs, [:original_filename, :mime_type, :file_size, :metadata])

  defp registration("external", key), do: Storage.validate_key(key)

  defp registration(disk, key) do
    case Storage.location(disk, key) do
      {:ok, _path} -> :ok
      error -> error
    end
  end
end
