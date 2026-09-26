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

  def artifact_dir(root) do
    dir =
      case System.get_env("BILIMBI_COMPOSITION_LOCK_DIR") do
        nil -> Path.join(root, ".scratchpad/composition-lock")
        path -> Path.expand(path, root)
      end

    if Path.expand(dir) == Path.expand(root),
      do: Mix.raise("composition lock directory cannot be the Platform root")

    dir
  end

  def pin!(root) do
    root = Path.expand(root)
    repositories = repositories(root)

    if repositories == [], do: Mix.raise("no mounted repositories to pin")

    lockfile = lockfile!(root)
    revisions = Enum.map(["." | repositories], &{&1, revision!(Path.join(root, &1))})

    manifest = manifest(revisions, digest!(lockfile))

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

    expected = Enum.map(["." | repositories], &{&1, revision!(Path.join(root, &1))})

    unless manifest == manifest(expected, digest!(Path.join(artifact_dir(root), "mix.lock"))) do
      Mix.raise("composition lock does not match mounted repository revisions or lock bytes")
    end

    :ok
  end

  defp mounted_lockfile!(root, _repositories) do
    dir = artifact_dir(root)
    lockfile = Path.join(dir, "mix.lock")

    unless File.regular?(lockfile) do
      if System.get_env("BILIMBI_COMPOSITION_PINNED") == "1" do
        Mix.raise("pinned composition lock is missing: #{lockfile}")
      end

      File.mkdir_p!(dir)
      File.cp!(Path.join(root, "mix.lock"), lockfile)
    end

    if System.get_env("BILIMBI_COMPOSITION_PINNED") == "1", do: check!(root)
    lockfile
  end

  defp manifest(revisions, lock_digest) do
    "bilimbi-composition-lock-v1\nlock-sha256 #{lock_digest}\n" <>
      Enum.map_join(revisions, "", fn {path, revision} -> "repo #{path} #{revision}\n" end)
  end

  defp revision!(path) do
    with {top, 0} <-
           System.cmd("git", ["rev-parse", "--show-toplevel"], cd: path, stderr_to_stdout: true),
         true <- Path.expand(String.trim(top)) == Path.expand(path),
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
