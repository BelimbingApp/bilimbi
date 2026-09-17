defmodule Mix.Tasks.Bilimbi.Cutover.Remap do
  @moduledoc """
  Remaps Belimbing stored values that Bilimbi interprets differently.

      mix bilimbi.cutover.remap [--dry-run] [--only STEPS] [--strict]

  Run once at cutover, after `mix bilimbi.schema.adopt` and before opening
  traffic. The schemas already match by construction; this step fixes stored
  values: `user_pins` URLs (+ recomputed hashes) and icons, notification
  payload URLs, `user_database_queries` icons, and a report-only scan of
  authz grants naming capabilities Bilimbi does not declare.

  Nothing is deleted. Pins with no Bilimbi equivalent stay in place and are
  named in the report, as are dedup-collision losers (which keep their
  original URL). Grants are never mutated.

  Options:

    * `--dry-run` — report what would change without writing. This is the
      expected first run on cutover day, and the read-only verifier for CI.
    * `--only STEPS` — comma-separated subset of
      `pins,query_icons,notifications,grants` (`icons` is accepted as an
      alias of `query_icons`).
    * `--strict` — exit non-zero when residue remains (unmapped pins,
      unmapped notification URLs, or grants for undeclared capabilities).
      Icon remainders are cosmetic and expected, so they never fail strict.

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
      OptionParser.parse!(args, strict: [dry_run: :boolean, only: :string, strict: :boolean])

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    only = parse_only(Keyword.get(opts, :only))
    dry_run? = Keyword.get(opts, :dry_run, false)
    strict? = Keyword.get(opts, :strict, false)

    with_repo!(Repo, fn repo ->
      case Cutover.run(repo: repo, dry_run: dry_run?, only: only) do
        {:ok, report} ->
          print_report(report)

          if strict? and Cutover.strict_residue?(report),
            do: Mix.raise("cutover residue remains (see above); refusing --strict success")

        {:error, message} ->
          Mix.raise(message)
      end
    end)
  end

  defp parse_only(nil), do: Cutover.steps()

  defp parse_only(only) when is_binary(only) do
    steps =
      only
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if steps == [] do
      Mix.raise(
        "expected --only STEPS with at least one of pins,query_icons,notifications,grants"
      )
    end

    Enum.map(steps, fn step ->
      case step do
        "pins" ->
          :pins

        "query_icons" ->
          :query_icons

        "query-icons" ->
          :query_icons

        "icons" ->
          :query_icons

        "notifications" ->
          :notifications

        "grants" ->
          :grants

        other ->
          Mix.raise(
            "unknown cutover step #{inspect(other)}; expected one of pins,query_icons,notifications,grants"
          )
      end
    end)
  end

  defp print_report(%{dry_run: dry_run?, steps: steps}) do
    Mix.shell().info(
      if dry_run?, do: "Cutover remap DRY RUN — no rows written.", else: "Cutover remap complete."
    )

    for step <- Cutover.steps(), Map.has_key?(steps, step) do
      print_step(step, Map.fetch!(steps, step))
    end

    if Cutover.strict_residue?(%{dry_run: dry_run?, steps: steps}) do
      Mix.shell().info(
        "Residue remains: unmapped pins, notification URLs, or undeclared-capability grants are listed above."
      )
    else
      Mix.shell().info("No blocking residue.")
    end
  end

  defp print_step(:pins, counts) do
    Mix.shell().info(
      "user_pins: examined=#{counts.examined} changed=#{counts.changed} unchanged=#{counts.unchanged} unmapped=#{counts.unmapped}"
    )

    Enum.each(counts.residue, fn entry ->
      Mix.shell().info(
        "  UNMAPPED pin_id=#{entry.pin_id} user_id=#{entry.user_id}#{who(entry)} label=#{inspect(entry.label)} url=#{inspect(entry.url)} reason=#{inspect(entry.reason)}"
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
    Mix.shell().info(
      "authz grants (report only, never mutated): examined=#{counts.examined} unchanged=#{counts.unchanged} undeclared=#{counts.unmapped}"
    )

    Enum.each(counts.role_grants, fn grant ->
      Mix.shell().info(
        "  UNDECLARED role grant_id=#{grant.grant_id} role=#{inspect(grant.role_code)} company_id=#{inspect(grant.company_id)} capability=#{inspect(grant.capability)}"
      )
    end)

    Enum.each(counts.principal_grants, fn grant ->
      Mix.shell().info(
        "  UNDECLARED principal grant_id=#{grant.grant_id} principal=#{grant.principal_type}:#{grant.principal_id} company_id=#{inspect(grant.company_id)} capability=#{inspect(grant.capability)}"
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
