defmodule Mix.Tasks.Bilimbi.Schema.Adopt do
  @moduledoc """
  Adopts an existing, verified Belimbing schema into Bilimbi's migration
  history without running baseline DDL.

      mix bilimbi.schema.adopt
      mix bilimbi.schema.adopt --prefix custom_schema

  Adoption refuses drift and never changes Laravel's `migrations` table.
  """

  use Mix.Task

  @shortdoc "Verifies and adopts an existing Belimbing schema"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, remaining} = OptionParser.parse!(args, strict: [prefix: :string])

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    with_repo!(Bilimbi.Base.Repo, fn repo -> adopt!(repo, opts) end)
  end

  defp adopt!(repo, opts) do
    case Bilimbi.Core.Compatibility.adopt(repo, opts) do
      {:ok, :adopted} ->
        Mix.shell().info("Existing Belimbing schema verified and adopted by Bilimbi.")

      {:ok, :advanced} ->
        Mix.shell().info("Verified schema and advanced the existing Bilimbi baseline ledger.")

      {:ok, :already_adopted} ->
        Mix.shell().info("Bilimbi compatibility baselines are already recorded.")

      {:error, {:schema_drift, errors}} ->
        details = Enum.map_join(errors, "\n", &"  - #{&1}")
        Mix.raise("Schema adoption refused because drift was detected:\n#{details}")

      {:error, {:ledger_conflict, versions}} ->
        Mix.raise(
          "Schema adoption refused because the Bilimbi ledger contains #{inspect(versions)}"
        )
    end
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
