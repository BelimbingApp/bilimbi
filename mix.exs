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
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup", "bilimbi.migrate"],
      "ecto.setup": ["ecto.create -r Bilimbi.Base.Repo", "bilimbi.migrate"],
      "ecto.reset": ["ecto.drop -r Bilimbi.Base.Repo", "ecto.setup"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "precommit.test",
        "bilimbi.contributions.verify"
      ],
      "precommit.test": &precommit_test/1
    ]
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

  defp report_skipped_precommit_tests([]), do: :ok

  defp report_skipped_precommit_tests(skipped) do
    Mix.shell().error("""
    Precommit stopped before running these test containers:
    #{Enum.map_join(skipped, "\n", &"  - #{&1}")}
    """)
  end
end
