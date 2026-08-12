defmodule Mix.Tasks.Bilimbi.Migrate do
  @moduledoc "Runs every installed module migration through Bilimbi's shared Repo and ledger."

  use Mix.Task

  @shortdoc "Runs installed Bilimbi module migrations"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run(
      "ecto.migrate",
      ["-r", "Bilimbi.Base.Repo", "--strict-version-order"] ++ migration_args() ++ args
    )
  end

  defp migration_args do
    Enum.flat_map(Bilimbi.Core.Compatibility.migration_paths(), fn path ->
      ["--migrations-path", path]
    end)
  end
end
