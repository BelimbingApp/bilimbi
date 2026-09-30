defmodule Bilimbi.Base.Artifacts.Storage do
  @moduledoc false
  import Bitwise

  # No caller filename reaches the filesystem. Reject symlinks in every path
  # component, public-serving directories, and roots with group/world access.
  # The OS account and operators controlling the root are trusted; it must not
  # be changed underneath the service by another process.
  def validate_root(root) when is_binary(root) and root != "" do
    with true <- Path.type(root) == :absolute,
         true <- root == Path.expand(root),
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

  def write(root, id, bytes) do
    with :ok <- validate_root(root),
         {:ok, file} <- File.open(path(root, id), [:write, :binary, :exclusive]) do
      result =
        with :ok <- File.chmod(path(root, id), 0o600),
             :ok <- IO.binwrite(file, bytes) do
          :file.sync(file)
        end

      File.close(file)
      result
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  def read(root, id) do
    with :ok <- validate_root(root),
         {:ok, stat} <- File.lstat(path(root, id)),
         true <- stat.type == :regular and (stat.mode &&& 0o777) == 0o600,
         {:ok, bytes} <- File.read(path(root, id)) do
      {:ok, bytes}
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  def delete(root, id) do
    with :ok <- validate_root(root) do
      case File.rm(path(root, id)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        _ -> {:error, :cleanup_pending}
      end
    end
  end

  def absent(root, id) do
    with :ok <- validate_root(root) do
      case File.lstat(path(root, id)) do
        {:error, :enoent} -> :ok
        {:ok, _} -> {:error, :bytes_present}
        {:error, _} -> {:error, :storage_unavailable}
      end
    end
  end

  defp path(root, id) do
    # IDs come only from Ecto.UUID generation or loaded UUID columns.
    {:ok, ^id} = Ecto.UUID.cast(id)
    Path.join(root, id)
  end

  defp directory_chain("/"), do: :ok

  defp directory_chain(path) do
    with :ok <- directory_chain(Path.dirname(path)),
         {:ok, %{type: :directory}} <- File.lstat(path) do
      :ok
    else
      _ -> {:error, :unsafe_storage_root}
    end
  end
end
