defmodule Mix.Tasks.Bilimbi.Migrations do
  @moduledoc "Displays migration status for every installed Bilimbi module."

  use Mix.Task

  @shortdoc "Lists installed Bilimbi module migrations"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run(
      "ecto.migrations",
      ["-r", "Bilimbi.Base.Repo"] ++ migration_args() ++ args
    )
  end

  defp migration_args do
    Enum.flat_map(Bilimbi.Core.Compatibility.migration_paths(), fn path ->
      ["--migrations-path", path]
    end)
  end
end
