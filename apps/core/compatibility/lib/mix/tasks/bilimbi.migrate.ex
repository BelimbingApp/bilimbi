defmodule Mix.Tasks.Bilimbi.Migrate do
  @moduledoc """
  Runs every installed module migration through Bilimbi's shared Repo and ledger.

  An existing Belimbing database that Bilimbi has not adopted is refused with
  the adoption sequence, as the release migrate command refuses it; migrating
  it would run baseline DDL against tables that already exist. In development
  `mix bilimbi.server` runs this task before it starts Phoenix.
  """

  use Mix.Task

  @shortdoc "Runs installed Bilimbi module migrations"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    Bilimbi.Base.ModuleRegistry.complete_modules!()
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

    ensure_adopted!(repo, Keyword.take(opts, [:prefix]))
    Bilimbi.Core.Compatibility.migrate(repo, opts)
  end

  defp ensure_adopted!(repo, opts) do
    Bilimbi.Core.Compatibility.ensure_adopted!(repo, opts)
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
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
