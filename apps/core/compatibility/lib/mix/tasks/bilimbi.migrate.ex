defmodule Mix.Tasks.Bilimbi.Migrate do
  @moduledoc "Runs every installed module migration through Bilimbi's shared Repo and ledger."

  use Mix.Task

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ConsoleAccess

  @shortdoc "Runs installed Bilimbi module migrations"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    with_repo!(Bilimbi.Base.Repo, &run(args, &1))
  end

  @doc false
  def run(args, repo) do
    {parsed, remaining} =
      OptionParser.parse!(args,
        strict: [prefix: :string, quiet: :boolean]
      )

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    opts =
      parsed
      |> Keyword.delete(:quiet)
      |> then(fn opts ->
        if parsed[:quiet], do: Keyword.put(opts, :log, false), else: opts
      end)

    versions = Bilimbi.Core.Compatibility.migrate(repo, opts)
    reconcile_console_access!(repo, Keyword.take(opts, [:prefix]), parsed[:quiet])
    versions
  end

  # The SQL console role's read grants are privileges on the tables the
  # migrations just created or changed, so they are reconciled on the one
  # path every deployment already runs after a schema change. A missing role
  # stops the task here, after the migrations, with instructions.
  defp reconcile_console_access!(repo, opts, quiet) do
    case Database.reconcile_console_access(repo, opts) do
      {:ok, summary} ->
        unless quiet, do: Mix.shell().info(ConsoleAccess.describe(summary))

      {:error, failure} ->
        Mix.raise(ConsoleAccess.explain(failure))
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
