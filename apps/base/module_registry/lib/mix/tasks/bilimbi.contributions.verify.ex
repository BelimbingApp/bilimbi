defmodule Mix.Tasks.Bilimbi.Contributions.Verify do
  @moduledoc false

  use Mix.Task

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @shortdoc "Verifies descriptor-owned module contributions"

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.start")
    snapshot = ContributionRegistry.snapshot!()

    provider_count =
      snapshot.consumers
      |> Map.values()
      |> Enum.count(&(&1 != []))

    Mix.shell().info(
      "Module contributions verified for #{provider_count} installed consumer snapshot(s)."
    )
  end

  def run(_arguments) do
    Mix.raise("mix bilimbi.contributions.verify accepts no arguments")
  end
end
