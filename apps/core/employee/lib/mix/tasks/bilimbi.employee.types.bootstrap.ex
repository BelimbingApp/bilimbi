defmodule Mix.Tasks.Bilimbi.Employee.Types.Bootstrap do
  @moduledoc "Ensures Bilimbi's canonical system employee types exist"

  use Mix.Task

  @shortdoc "Ensures Bilimbi's canonical system employee types exist"

  @impl Mix.Task
  def run(args) do
    if args != [], do: Mix.raise("this task does not accept arguments")

    Mix.Task.run("app.start")
    :ok = Bilimbi.Core.Employee.ensure_system_types()
    Mix.shell().info("Bilimbi system employee types are ready.")
  end
end
