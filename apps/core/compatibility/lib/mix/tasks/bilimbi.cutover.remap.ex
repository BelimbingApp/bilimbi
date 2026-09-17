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

    with_repo!(Repo, fn repo ->
      case Cutover.run(repo: repo, dry_run: dry_run?, prefix: prefix) do
        {:ok, report} -> print_report(report)
        {:error, message} -> Mix.raise(message)
      end
    end)
  end

  defp print_report(%{dry_run: dry_run?, steps: steps}) do
    Mix.shell().info(
      if dry_run?, do: "Cutover remap DRY RUN — no rows written.", else: "Cutover remap complete."
    )

    for step <- Cutover.steps() do
      print_step(step, Map.fetch!(steps, step))
    end
  end

  defp print_step(:pins, counts) do
    Mix.shell().info(
      "user_pins: examined=#{counts.examined} changed=#{counts.changed} unchanged=#{counts.unchanged} unmapped=#{counts.unmapped} icons_changed=#{counts.icons_changed}"
    )

    Enum.each(counts.residue, fn entry ->
      Mix.shell().info(
        "  UNMAPPED pin_id=#{entry.pin_id} user_id=#{entry.user_id}#{who(entry)} label=#{inspect(entry.label)} url=#{inspect(entry.url)} reason=#{inspect(entry.reason)}"
      )
    end)

    Enum.each(counts.remainder, fn entry ->
      Mix.shell().info(
        "  REMAINDER icon=#{inspect(entry.icon)} example_pin_id=#{entry.example_pin_id} user_id=#{entry.user_id}"
      )
    end)
  end

  defp print_step(:query_icons, counts) do
    Mix.shell().info(
      "user_database_queries icons: examined=#{counts.examined} changed=#{counts.changed} unchanged=#{counts.unchanged} remainder=#{counts.unmapped}"
    )

    Enum.each(counts.remainder, fn entry ->
      Mix.shell().info(
        "  REMAINDER icon=#{inspect(entry.icon)} example_query_id=#{entry.example_query_id} user_id=#{entry.user_id}"
      )
    end)
  end

  defp print_step(:notifications, counts) do
    Mix.shell().info(
      "notifications: examined=#{counts.examined} changed=#{counts.changed} unchanged=#{counts.unchanged} unmapped=#{counts.unmapped}"
    )

    Enum.each(counts.residue, fn entry ->
      Mix.shell().info(
        "  UNMAPPED notification_id=#{entry.notification_id} notifiable_id=#{entry.notifiable_id} type=#{inspect(entry.type)} url=#{inspect(entry.url)} reason=#{inspect(entry.reason)}"
      )
    end)
  end

  defp print_step(:grants, counts) do
    Mix.shell().info("authz grants (report only, never mutated): undeclared=#{counts.undeclared}")

    Enum.each(counts.role_grants, fn grant ->
      Mix.shell().info(
        "  UNDECLARED role grant role_id=#{grant.role_id} capability=#{inspect(grant.capability)}"
      )
    end)

    Enum.each(counts.principal_grants, fn grant ->
      Mix.shell().info(
        "  UNDECLARED principal grant principal=#{grant.principal_type}:#{grant.principal_id} company_id=#{inspect(grant.company_id)} capability=#{inspect(grant.capability)} allowed=#{grant.allowed}"
      )
    end)
  end

  defp who(%{user_email: nil}), do: ""
  defp who(%{user_email: email}), do: " (#{email})"

  defp with_repo!(repo, operation) do
    case Ecto.Migrator.with_repo(repo, operation, mode: :temporary) do
      {:ok, result, _started_apps} ->
        result

      {:error, error} ->
        Mix.raise("Could not start repo #{inspect(repo)}, error: #{inspect(error)}")
    end
  end
end
