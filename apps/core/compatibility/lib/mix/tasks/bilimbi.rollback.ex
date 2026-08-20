defmodule Mix.Tasks.Bilimbi.Rollback do
  @moduledoc "Rolls back installed Bilimbi module migrations in shared-ledger order."

  use Mix.Task

  @shortdoc "Rolls back installed Bilimbi module migrations"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run(
      "ecto.rollback",
      ["-r", "Bilimbi.Base.Repo"] ++ migration_args() ++ args
    )
  end

  defp migration_args do
    Enum.flat_map(Bilimbi.Core.Compatibility.migration_paths(), fn path ->
      ["--migrations-path", path]
    end)
  end
end
