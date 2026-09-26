defmodule Bilimbi.CompositionLock do
  @moduledoc """
  Selects one lock for the entire discovered source composition.

  The Platform lock belongs to the unmounted checkout. Mounted repositories
  resolve together into one ignored composition artifact, never into the
  Platform lock. CI sets `BILIMBI_COMPOSITION_PINNED=1` and uses the published
  artifact before `mix deps.get --check-locked`.
  """

  @mounts ["domains", "extensions"]

  def lockfile!(root) do
    root = Path.expand(root)

    case repositories(root) do
      [] -> Path.join(root, "mix.lock")
      repositories -> mounted_lockfile!(root, repositories)
    end
  end

  def repositories(root) do
    for role <- @mounts,
        path <- Path.wildcard(Path.join([root, "apps", role, "*"])),
        File.dir?(path) do
      Path.relative_to(path, root)
    end
    |> Enum.sort()
  end

  def artifact_dir(root), do: Path.join(root, ".scratchpad/composition-lock")

  def pin!(root) do
    root = Path.expand(root)
    repositories = repositories(root)

    if repositories == [], do: Mix.raise("no mounted repositories to pin")

    lockfile = lockfile!(root)
    revisions = Enum.map(["." | repositories], &{&1, revision!(Path.join(root, &1))})

    manifest = manifest(revisions, digest!(Path.join(root, "mix.lock")), digest!(lockfile))

    File.write!(Path.join(artifact_dir(root), "manifest.txt"), manifest)
    manifest
  end

  def check!(root) do
    root = Path.expand(root)
    repositories = repositories(root)

    if repositories == [], do: Mix.raise("no mounted repositories to check")

    path = Path.join(artifact_dir(root), "manifest.txt")

    manifest =
      try do
        File.read!(path)
      rescue
        _ -> Mix.raise("missing or invalid composition revision manifest: #{path}")
      end

    platform_digest = digest!(Path.join(root, "mix.lock"))

    unless platform_lock_digest(manifest) == platform_digest do
      Mix.raise(
        "Platform mix.lock changed since the composition lock was pinned; " <>
          "re-derive the overlay without BILIMBI_COMPOSITION_PINNED and publish a new pin"
      )
    end

    expected = Enum.map(["." | repositories], &{&1, revision!(Path.join(root, &1))})
    lock_digest = digest!(Path.join(artifact_dir(root), "mix.lock"))

    unless manifest == manifest(expected, platform_digest, lock_digest) do
      Mix.raise("composition lock does not match mounted repository revisions or lock bytes")
    end

    :ok
  end

  defp mounted_lockfile!(root, _repositories) do
    lockfile = Path.join(artifact_dir(root), "mix.lock")

    if System.get_env("BILIMBI_COMPOSITION_PINNED") == "1" do
      unless File.regular?(lockfile),
        do: Mix.raise("pinned composition lock is missing: #{lockfile}")

      checked!(root)
    else
      derive!(root, lockfile)
    end

    lockfile
  end

  defp checked!(root) do
    key = {__MODULE__, :checked, root}

    unless :persistent_term.get(key, false) do
      check!(root)
      :persistent_term.put(key, true)
    end
  end

  defp derive!(root, lockfile) do
    platform_lock = Path.join(root, "mix.lock")
    platform_digest = digest!(platform_lock)
    manifest_path = Path.join(Path.dirname(lockfile), "manifest.txt")

    recorded =
      case File.read(manifest_path) do
        {:ok, manifest} -> platform_lock_digest(manifest)
        {:error, _} -> nil
      end

    cond do
      not File.regular?(lockfile) ->
        File.mkdir_p!(Path.dirname(lockfile))
        File.cp!(platform_lock, lockfile)
        File.write!(manifest_path, manifest([], platform_digest, nil))

      recorded != platform_digest ->
        lockfile
        |> Mix.Dep.Lock.read()
        |> Map.merge(Mix.Dep.Lock.read(platform_lock))
        |> write_lock!(lockfile)

        File.write!(manifest_path, manifest([], platform_digest, nil))
        Mix.shell().info("Re-derived composition lock overlay from the changed Platform mix.lock")

      true ->
        :ok
    end
  end

  defp write_lock!(lock, path) do
    lines =
      for {app, entry} <- Enum.sort(lock), entry != nil do
        ~s(  "#{app}": #{inspect(entry, limit: :infinity)},\n)
      end

    File.write!(path, ["%{\n", lines, "}\n"])
  end

  defp platform_lock_digest(manifest) do
    case Regex.run(~r/^platform-lock-sha256 (\S+)$/m, manifest) do
      [_, digest] -> digest
      nil -> nil
    end
  end

  defp manifest(revisions, platform_digest, lock_digest) do
    "bilimbi-composition-lock-v1\nplatform-lock-sha256 #{platform_digest}\n" <>
      if(lock_digest, do: "lock-sha256 #{lock_digest}\n", else: "") <>
      Enum.map_join(revisions, "", fn {path, revision} -> "repo #{path} #{revision}\n" end)
  end

  defp revision!(path) do
    with {"\n", 0} <-
           System.cmd("git", ["rev-parse", "--show-prefix"], cd: path, stderr_to_stdout: true),
         {revision, 0} <-
           System.cmd("git", ["rev-parse", "HEAD"], cd: path, stderr_to_stdout: true),
         {"", 0} <-
           System.cmd("git", ["status", "--porcelain", "--untracked-files=no"],
             cd: path,
             stderr_to_stdout: true
           ) do
      String.trim(revision)
    else
      _ ->
        Mix.raise(
          "composition source must be an independent clean Git repository with a HEAD: #{path}"
        )
    end
  end

  defp digest!(path),
    do: path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end

defmodule Mix.Tasks.Bilimbi.Composition.Lock do
  use Mix.Task

  @shortdoc "Pin or check the mounted composition lock artifact"

  def run(["--pin"]), do: Bilimbi.CompositionLock.pin!(File.cwd!())
  def run(["--check"]), do: Bilimbi.CompositionLock.check!(File.cwd!())
  def run(_), do: Mix.raise("usage: mix bilimbi.composition.lock --pin | --check")
end
