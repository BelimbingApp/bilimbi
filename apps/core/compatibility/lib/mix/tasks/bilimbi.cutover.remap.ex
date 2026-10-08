defmodule Mix.Tasks.Bilimbi.Cutover.Remap do
  @moduledoc """
  Remaps Belimbing stored values that Bilimbi interprets differently.

      mix bilimbi.cutover.remap [--dry-run] [--prefix SCHEMA]

  Run once at cutover, after `mix bilimbi.schema.adopt` and before opening
  traffic. The schemas already match by construction; this step fixes stored
  values: `user_pins` URLs (+ recomputed hashes) and icons, notification
  payload URLs, `user_database_queries` icons, and a report-only scan of
  authz grants naming capabilities Bilimbi does not declare.

  Nothing is deleted. Pins with no Bilimbi equivalent keep their URL and hash
  and are named in the report, as are dedup-collision losers; their icons are
  still repaired. Grants are never mutated.

  Options:

    * `--dry-run` — report what would change without writing. This is the
      expected first run on cutover day, and the read-only verifier for CI.
    * `--prefix SCHEMA` — the PostgreSQL schema to remap, default `public`.
      Pass the same schema `mix bilimbi.schema.verify` and
      `mix bilimbi.schema.adopt` were pointed at.

  The run is idempotent: running it twice is safe and the second run
  reports `changed: 0` with the same residue.
  """

  use Mix.Task

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility.Cutover

  @shortdoc "Remaps Belimbing cutover values Bilimbi interprets differently"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, remaining} =
      OptionParser.parse!(args, strict: [dry_run: :boolean, prefix: :string])

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    dry_run? = Keyword.get(opts, :dry_run, false)
    prefix = Keyword.get(opts, :prefix, "public")

    ContributionRegistry.install!()

    with_repo!(Repo, fn repo ->
      case Cutover.run(repo: repo, dry_run: dry_run?, prefix: prefix) do
        {:ok, report} -> print_report(report)
        {:error, message} -> Mix.raise(message)
      end
    end)
  end

  defp print_report(report) do
    Enum.each(Cutover.report_lines(report), fn line -> Mix.shell().info(line) end)
  end

  defp with_repo!(repo, operation) do
    case Ecto.Migrator.with_repo(repo, operation, mode: :temporary) do
      {:ok, result, _started_apps} ->
        result

      {:error, error} ->
        Mix.raise("Could not start repo #{inspect(repo)}, error: #{inspect(error)}")
    end
  end
end
