defmodule Bilimbi.Base.Media.Storage do
  @moduledoc false
  import Bitwise
  alias Bilimbi.Base.Settings

  # Disk names are durable Belimbing data; operators map them to private local
  # roots. Never concatenate an unvalidated stored key, follow a symlink, or
  # treat the external-link sentinel as a filesystem location.
  def location(disk, key) do
    roots = Settings.get("media.disks")
    root = if is_map(roots), do: Map.get(roots, disk)

    with :ok <- validate_root(root),
         :ok <- validate_key(key) do
      {:ok, Path.join(root, key)}
    end
  end

  def validate_key(key) when is_binary(key) and key != "" do
    if byte_size(key) <= 255 and String.valid?(key) and Path.type(key) == :relative and
         not String.contains?(key, ["\\", <<0>>]) and
         Enum.all?(String.split(key, "/"), &(&1 not in ["", ".", ".."])),
       do: :ok,
       else: {:error, :unsafe_storage_key}
  end

  def validate_key(_), do: {:error, :unsafe_storage_key}

  def write(disk, key, bytes) do
    with {:ok, path} <- location(disk, key),
         :ok <- make_directories(Path.dirname(path)),
         {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      result =
        with :ok <- File.chmod(path, 0o600), :ok <- IO.binwrite(file, bytes), do: :file.sync(file)

      File.close(file)
      if result != :ok, do: File.rm(path)
      result
    else
      {:error, :eexist} -> {:error, :storage_key_exists}
      {:error, _} = error -> error
    end
  end

  def read(disk, key) do
    with {:ok, path} <- location(disk, key),
         :ok <- directory_chain(Path.dirname(path)),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, bytes}
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  def delete("external", _key), do: :ok

  def delete(disk, key) do
    with {:ok, path} <- location(disk, key), :ok <- directory_chain(Path.dirname(path)) do
      case File.lstat(path) do
        {:error, :enoent} -> :ok
        {:ok, %{type: :regular}} -> File.rm(path)
        _ -> {:error, :unsafe_storage_key}
      end
    end
  end

  def validate_root(root) when is_binary(root) and root != "" do
    with true <- Path.type(root) == :absolute and Path.expand(root) == root,
         false <- Enum.any?(Path.split(root), &(&1 in ["static", "public", "assets"])),
         :ok <- directory_chain(root),
         {:ok, stat} <- File.lstat(root),
         true <- (stat.mode &&& 0o777) == 0o700 do
      :ok
    else
      _ -> {:error, :unsafe_storage_root}
    end
  end

  def validate_root(_), do: {:error, :storage_not_configured}

  defp make_directories("/"), do: :ok

  defp make_directories(path) do
    with :ok <- make_directories(Path.dirname(path)) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} ->
          :ok

        {:error, :enoent} ->
          case File.mkdir(path) do
            :ok -> File.chmod(path, 0o700)
            {:error, :eexist} -> directory_chain(path)
            error -> error
          end

        _ ->
          {:error, :unsafe_storage_key}
      end
    end
  end

  defp directory_chain("/"), do: :ok

  defp directory_chain(path) do
    with :ok <- directory_chain(Path.dirname(path)),
         {:ok, %{type: :directory}} <- File.lstat(path) do
      :ok
    else
      _ -> {:error, :unsafe_storage_key}
    end
  end
end
