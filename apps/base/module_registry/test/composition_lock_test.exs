defmodule Bilimbi.Base.ModuleRegistry.CompositionLockTest do
  use ExUnit.Case, async: false

  @helper Path.expand("../../../../mix/composition_lock.exs", __DIR__)
  Code.require_file(@helper)

  setup do
    root = Path.join(System.tmp_dir!(), "bilimbi-lock-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "mix.lock"), "%{}\n")
    git!(root, ["init", "-q"])

    git!(root, [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "-q",
      "--allow-empty",
      "-m",
      "platform"
    ])

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "unmounted builds keep the Platform lock and mounted builds share an overlay", %{
    root: root
  } do
    platform_lock = Path.join(root, "mix.lock")
    assert Bilimbi.CompositionLock.lockfile!(root) == platform_lock

    mount!(root, "domains", "factory")
    mount!(root, "extensions", "adapter")
    overlay = Bilimbi.CompositionLock.lockfile!(root)
    assert overlay == Path.join(root, ".scratchpad/composition-lock/mix.lock")
    assert File.read!(overlay) == "%{}\n"

    File.write!(overlay, "%{sample: :mounted}\n")
    assert Bilimbi.CompositionLock.lockfile!(root) == overlay
    Bilimbi.CompositionLock.pin!(root)
    assert :ok == Bilimbi.CompositionLock.check!(root)

    File.rm_rf!(Path.join(root, "apps/extensions/adapter"))

    assert_raise Mix.Error, ~r/does not match mounted repository revisions/, fn ->
      Bilimbi.CompositionLock.check!(root)
    end

    File.rm_rf!(Path.join(root, "apps/domains/factory"))
    assert Bilimbi.CompositionLock.lockfile!(root) == platform_lock
    assert File.read!(platform_lock) == "%{}\n"
    assert File.read!(overlay) == "%{sample: :mounted}\n"
  end

  test "pinned mode rejects a modified lock and changed revision", %{root: root} do
    repo = mount!(root, "domains", "factory")
    overlay = Bilimbi.CompositionLock.lockfile!(root)
    Bilimbi.CompositionLock.pin!(root)
    File.write!(overlay, "%{other: :version}\n")

    assert_raise Mix.Error, ~r/does not match/, fn ->
      Bilimbi.CompositionLock.check!(root)
    end

    File.write!(overlay, "%{}\n")

    git!(repo, [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "-q",
      "--allow-empty",
      "-m",
      "next"
    ])

    assert_raise Mix.Error, ~r/does not match/, fn ->
      Bilimbi.CompositionLock.check!(root)
    end
  end

  test "pinned deps.get --check-locked checks the published artifact", %{root: root} do
    mount!(root, "domains", "factory")

    File.write!(
      Path.join(root, "mix.exs"),
      "Code.require_file(#{inspect(@helper)})\n" <>
        "defmodule Fixture.PinnedMixProject do\n" <>
        "  use Mix.Project\n" <>
        "  def project, do: [app: :pinned, version: \"0.1.0\", lockfile: Bilimbi.CompositionLock.lockfile!(__DIR__), deps: []]\n" <>
        "end\n"
    )

    git!(root, ["add", "mix.exs", "mix.lock"])

    git!(root, [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "-q",
      "-m",
      "project"
    ])

    overlay = Bilimbi.CompositionLock.lockfile!(root)
    Bilimbi.CompositionLock.pin!(root)

    {output, status} =
      System.cmd(System.find_executable("mix"), ["deps.get", "--check-locked"],
        cd: root,
        env: [{"BILIMBI_COMPOSITION_PINNED", "1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(overlay, "%{wrong: :lock}\n")

    {output, status} =
      System.cmd(System.find_executable("mix"), ["deps.get", "--check-locked"],
        cd: root,
        env: [{"BILIMBI_COMPOSITION_PINNED", "1"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "composition lock does not match"
  end

  test "deps.unlock --unused changes only the mounted overlay", %{root: root} do
    mount!(root, "domains", "factory")

    File.write!(
      Path.join(root, "mix.exs"),
      "Code.require_file(#{inspect(@helper)})\n" <>
        "defmodule Fixture.UnlockMixProject do\n" <>
        "  use Mix.Project\n" <>
        "  def project, do: [app: :unlock, version: \"0.1.0\", lockfile: Bilimbi.CompositionLock.lockfile!(__DIR__), deps: []]\n" <>
        "end\n"
    )

    overlay = Bilimbi.CompositionLock.lockfile!(root)
    File.write!(overlay, inspect(%{jason: Map.fetch!(Mix.Dep.Lock.read(), :jason)}))

    {output, status} =
      System.cmd(System.find_executable("mix"), ["deps.unlock", "--unused"],
        cd: root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "jason"
    assert File.read!(Path.join(root, "mix.lock")) == "%{}\n"
    refute File.read!(overlay) =~ "jason"
  end

  test "a Platform lock-only bump re-derives the overlay and keeps mounted-only packages", %{
    root: root
  } do
    platform_lock = Path.join(root, "mix.lock")
    File.write!(platform_lock, ~s(%{"phoenix": {:hex, :phoenix, "1.8.10"}}\n))
    mount!(root, "domains", "factory")
    overlay = Bilimbi.CompositionLock.lockfile!(root)

    File.write!(
      overlay,
      ~s(%{"phoenix": {:hex, :phoenix, "1.8.10"}, "factory_only": {:hex, :factory_only, "0.3.0"}}\n)
    )

    assert Bilimbi.CompositionLock.lockfile!(root) == overlay
    assert Mix.Dep.Lock.read(overlay).phoenix == {:hex, :phoenix, "1.8.10"}

    File.write!(platform_lock, ~s(%{"phoenix": {:hex, :phoenix, "1.8.11"}}\n))

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert Bilimbi.CompositionLock.lockfile!(root) == overlay
      end)

    assert output =~ "Re-derived composition lock overlay"

    assert Mix.Dep.Lock.read(overlay) == %{
             phoenix: {:hex, :phoenix, "1.8.11"},
             factory_only: {:hex, :factory_only, "0.3.0"}
           }

    assert ExUnit.CaptureIO.capture_io(fn -> Bilimbi.CompositionLock.lockfile!(root) end) == ""
    assert File.read!(platform_lock) == ~s(%{"phoenix": {:hex, :phoenix, "1.8.11"}}\n)
  end

  test "pinned mode refuses a Platform lock that changed after pinning", %{root: root} do
    mount!(root, "domains", "factory")
    Bilimbi.CompositionLock.lockfile!(root)
    Bilimbi.CompositionLock.pin!(root)
    File.write!(Path.join(root, "mix.lock"), ~s(%{"phoenix": {:hex, :phoenix, "1.8.11"}}\n))

    assert_raise Mix.Error,
                 ~r/Platform mix.lock changed since the composition lock was pinned/,
                 fn ->
                   Bilimbi.CompositionLock.check!(root)
                 end
  end

  test "two mounted repositories with divergent dependency sources are rejected", %{
    root: root
  } do
    a = mount!(root, "domains", "a")
    b = mount!(root, "extensions", "b")

    for {dir, version} <- [{"shared-1.5", "1.5.0"}, {"shared-1.4", "1.4.0"}] do
      path = Path.join([root, "packages", dir])
      File.mkdir_p!(path)
      File.write!(Path.join(path, "mix.exs"), mix_project(:shared, version, "[]"))
    end

    File.write!(
      Path.join(a, "mix.exs"),
      mix_project(:a, "0.1.0", "[{:shared, \"~> 1.5\", path: \"../../../packages/shared-1.5\"}]")
    )

    File.write!(
      Path.join(b, "mix.exs"),
      mix_project(
        :b,
        "0.1.0",
        "[{:shared, \"~> 1.4.0\", path: \"../../../packages/shared-1.4\"}]"
      )
    )

    resolve = fn deps ->
      File.write!(
        Path.join(root, "mix.exs"),
        "Code.require_file(#{inspect(@helper)})\n" <>
          String.replace(
            mix_project(:composition, "0.1.0", deps),
            "version: \"0.1.0\",",
            "version: \"0.1.0\", lockfile: Bilimbi.CompositionLock.lockfile!(__DIR__),"
          )
      )

      System.cmd(System.find_executable("mix"), ["deps.loadpaths", "--no-compile"],
        cd: root,
        stderr_to_stdout: true
      )
    end

    assert {_, 0} = resolve.("[{:a, path: \"apps/domains/a\"}]")
    assert {_, 0} = resolve.("[{:b, path: \"apps/extensions/b\"}]")

    {output, status} =
      resolve.("[{:a, path: \"apps/domains/a\"}, {:b, path: \"apps/extensions/b\"}]")

    assert status != 0
    assert output =~ "different specs were given for the shared app"
    assert File.regular?(Path.join(root, ".scratchpad/composition-lock/mix.lock"))
    assert File.read!(Path.join(root, "mix.lock")) == "%{}\n"
  end

  test "two mounted repositories with incompatible transitive version requirements fail", %{
    root: root
  } do
    a = mount!(root, "domains", "a")
    b = mount!(root, "extensions", "b")
    shared = Path.join(root, "packages/shared")
    File.mkdir_p!(shared)
    git!(shared, ["init", "-q"])

    revisions =
      for version <- ["1.4.0", "1.5.0"], into: %{} do
        File.write!(Path.join(shared, "mix.exs"), mix_project(:shared, version, "[]"))
        git!(shared, ["add", "mix.exs"])

        git!(shared, [
          "-c",
          "user.name=Test",
          "-c",
          "user.email=test@example.com",
          "commit",
          "-q",
          "-m",
          version
        ])

        git!(shared, ["tag", "v#{version}"])
        {version, shared |> git!(["rev-parse", "HEAD"]) |> String.trim()}
      end

    File.write!(
      Path.join(a, "mix.exs"),
      mix_project(:a, "0.1.0", "[{:shared, \"~> 1.5\", git: #{inspect(shared)}}]")
    )

    File.write!(
      Path.join(b, "mix.exs"),
      mix_project(:b, "0.1.0", "[{:shared, \"~> 1.4.0\", git: #{inspect(shared)}}]")
    )

    overlay = Bilimbi.CompositionLock.lockfile!(root)

    resolve = fn deps, version ->
      File.write!(
        Path.join(root, "mix.exs"),
        "Code.require_file(#{inspect(@helper)})\n" <>
          String.replace(
            mix_project(:composition, "0.1.0", deps),
            "version: \"0.1.0\",",
            "version: \"0.1.0\", lockfile: Bilimbi.CompositionLock.lockfile!(__DIR__),"
          )
      )

      File.rm_rf!(Path.join(root, "deps"))
      File.rm_rf!(Path.join(root, "_build"))

      File.write!(
        overlay,
        inspect(%{shared: {:git, shared, Map.fetch!(revisions, version), []}})
      )

      mix = System.find_executable("mix")
      {output, 0} = System.cmd(mix, ["deps.get"], cd: root, stderr_to_stdout: true)
      assert Mix.Dep.Lock.read(overlay).shared == {:git, shared, revisions[version], []}, output
      System.cmd(mix, ["deps.loadpaths"], cd: root, stderr_to_stdout: true)
    end

    both = "[{:a, path: \"apps/domains/a\"}, {:b, path: \"apps/extensions/b\"}]"

    assert {_, 0} = resolve.("[{:a, path: \"apps/domains/a\"}]", "1.5.0")
    assert {_, 0} = resolve.("[{:b, path: \"apps/extensions/b\"}]", "1.4.0")

    for version <- ["1.4.0", "1.5.0"] do
      {output, status} = resolve.(both, version)
      assert status != 0
      assert output =~ "does not match the requirement"
    end

    assert File.read!(Path.join(root, "mix.lock")) == "%{}\n"
  end

  defp mount!(root, role, name) do
    path = Path.join([root, "apps", role, name])
    File.mkdir_p!(path)
    File.write!(Path.join(path, "bilimbi.container.exs"), "[]\n")
    git!(path, ["init", "-q"])
    git!(path, ["add", "bilimbi.container.exs"])

    git!(path, [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "-q",
      "-m",
      "mounted"
    ])

    path
  end

  defp git!(dir, args) do
    {output, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    output
  end

  defp mix_project(app, version, deps) do
    "defmodule Fixture.#{app |> Atom.to_string() |> Macro.camelize()}MixProject do\n  use Mix.Project\n  def project, do: [app: #{inspect(app)}, version: #{inspect(version)}, deps: #{deps}]\nend\n"
  end
end
