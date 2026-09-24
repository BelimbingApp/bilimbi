defmodule Bilimbi.Umbrella.MixProject do
  use Mix.Project

  @precommit_test_containers ["apps/core", "apps/base", "apps/web"]

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # CI runs `mix dialyzer` from this umbrella root, so the PLT is built here.
      # `mix bilimbi.screenshot` (apps/web) is the first shipped Mix task, and its
      # `Mix.*` surface needs the Mix application in the PLT to type-check. PLT-only
      # — this adds :mix to Dialyzer's analysis, not to any app's runtime.
      dialyzer: [plt_add_apps: [:mix]],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      # Required to format HEEx from the umbrella root.
      {:phoenix_live_view, "~> 1.2.0"},
      # Project-wide, open-source development and CI checks.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false},
      # Docs for the locked dependency versions. No `usage_rules:` key, and
      # never sync those files into a guide.
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup", "bilimbi.migrate"],
      "bilimbi.server": [&prepare_bilimbi_server/1, "bilimbi.server"],
      "ecto.setup": ["ecto.create -r Bilimbi.Base.Repo", "bilimbi.migrate"],
      "ecto.reset": ["ecto.drop -r Bilimbi.Base.Repo", "ecto.setup"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "assets.test",
        "precommit.test",
        "bilimbi.contributions.verify"
      ],
      "precommit.test": &precommit_test/1,
      "assets.test": &assets_test/1
    ]
  end

  defp prepare_bilimbi_server(_args) do
    Mix.shell().info("Checking and fetching locked dependencies before starting Bilimbi.")
    Mix.Task.run("deps.get")
  end

  defp precommit_test(_args) do
    mix = System.find_executable("mix") || Mix.raise("could not find mix executable")

    Enum.reduce_while(@precommit_test_containers, @precommit_test_containers, fn container,
                                                                                 remaining ->
      Mix.shell().info("==> #{container}")

      case System.cmd(mix, ["test"],
             cd: Path.expand(container, __DIR__),
             into: IO.stream(:stdio, :line),
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          {:cont, tl(remaining)}

        {_output, status} ->
          report_skipped_precommit_tests(tl(remaining))
          exit({:shutdown, status})
      end
    end)

    :ok
  end

  # The LiveView hooks in apps/web/assets/js are tested in Node, with the test
  # runner Node ships and one DOM library (apps/web/assets/package.json). The
  # library is installed on first use and again whenever the lockfile changes.
  defp assets_test(_args) do
    dir = Path.expand("apps/web/assets", __DIR__)

    npm =
      System.find_executable("npm") ||
        Mix.raise("mix assets.test needs Node.js 22 or later, with npm, on the PATH")

    unless assets_test_installed?(dir), do: npm!(npm, ["ci", "--no-audit", "--no-fund"], dir)

    npm!(npm, ["test"], dir)
  end

  # `npm ci` writes node_modules/.package-lock.json last, so it is newer than
  # the lockfile it installed from until that lockfile changes.
  defp assets_test_installed?(dir) do
    with {:ok, %{mtime: installed}} <-
           File.stat(Path.join(dir, "node_modules/.package-lock.json")),
         {:ok, %{mtime: locked}} <- File.stat(Path.join(dir, "package-lock.json")) do
      installed >= locked
    else
      _missing -> false
    end
  end

  defp npm!(npm, args, dir) do
    case System.cmd(npm, args, cd: dir, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {_output, status} -> exit({:shutdown, status})
    end
  end

  defp report_skipped_precommit_tests([]), do: :ok

  defp report_skipped_precommit_tests(skipped) do
    Mix.shell().error("""
    Precommit stopped before running these test containers:
    #{Enum.map_join(skipped, "\n", &"  - #{&1}")}
    """)
  end
end
