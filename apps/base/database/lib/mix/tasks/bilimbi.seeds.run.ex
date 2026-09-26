defmodule Mix.Tasks.Bilimbi.Seeds.Run do
  @moduledoc "Runs explicitly registered Bilimbi production seed providers."

  use Mix.Task

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.ModuleRegistry

  @shortdoc "Runs pending Bilimbi production seeds"

  @impl true
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: [provider: :keep])

    if positional != [] do
      Mix.raise("unexpected arguments: #{Enum.join(positional, " ")}")
    end

    Mix.Task.run("app.start")
    ModuleRegistry.complete_modules!()

    seeds =
      opts
      |> Keyword.get_values(:provider)
      |> Enum.map(&provider_module!/1)
      |> Database.installed_production_seeds!()

    case Database.run_production_seeds(seeds) do
      {:ok, []} ->
        Mix.shell().info("No production seeds are registered.")

      {:ok, results} ->
        Enum.each(results, fn result ->
          Mix.shell().info("#{result.status}: #{result.id}")
        end)

      {:error, failure} ->
        Mix.raise("production seed #{failure.seed_id} failed: #{inspect(failure.reason)}")
    end
  end

  @doc false
  def provider_module!(name) do
    segments = String.split(name, ".", trim: true)

    provider =
      try do
        Module.safe_concat(segments)
      rescue
        ArgumentError -> Module.concat(segments)
      end

    if Code.ensure_loaded?(provider) do
      provider
    else
      Mix.raise("unknown production seed provider: #{name}")
    end
  rescue
    ArgumentError -> Mix.raise("unknown production seed provider: #{name}")
  end
end
