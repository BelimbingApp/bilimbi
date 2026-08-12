defmodule Mix.Tasks.Bilimbi.Seeds.Run do
  @moduledoc "Runs explicitly registered Bilimbi production seed providers."

  use Mix.Task

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ProductionSeedProvider
  alias Bilimbi.Base.ModuleRegistry

  @shortdoc "Runs pending Bilimbi production seeds"
  @provider_key :bilimbi_production_seed_provider

  @impl true
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: [provider: :keep])

    if positional != [] do
      Mix.raise("unexpected arguments: #{Enum.join(positional, " ")}")
    end

    Mix.Task.run("app.start")

    providers =
      discovered_providers() ++
        Enum.map(Keyword.get_values(opts, :provider), &provider_module!/1)

    providers = Enum.uniq(providers)
    seeds = Enum.flat_map(providers, &provider_seeds!/1)

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

  defp discovered_providers do
    ModuleRegistry.installed_modules!()
    |> Enum.flat_map(fn descriptor ->
      descriptor.otp_app
      |> Application.get_env(@provider_key, [])
      |> List.wrap()
    end)
  end

  defp provider_module!(name) do
    name
    |> String.split(".", trim: true)
    |> Module.safe_concat()
  rescue
    ArgumentError -> Mix.raise("unknown production seed provider: #{name}")
  end

  defp provider_seeds!(provider) do
    unless Code.ensure_loaded?(provider) and function_exported?(provider, :production_seeds, 0) do
      Mix.raise("#{inspect(provider)} is not a production seed provider")
    end

    behaviours =
      provider.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless ProductionSeedProvider in behaviours do
      Mix.raise(
        "#{inspect(provider)} must implement Bilimbi.Base.Database.ProductionSeedProvider"
      )
    end

    otp_app =
      Application.get_application(provider) ||
        Mix.raise("#{inspect(provider)} is not loaded from an OTP application")

    descriptor =
      ModuleRegistry.installed_modules!()
      |> Enum.find(&(&1.otp_app == otp_app)) ||
        Mix.raise("#{inspect(otp_app)} has no installed Bilimbi module metadata")

    seeds = provider.production_seeds()

    Enum.each(seeds, fn seed ->
      unless seed.module_id == descriptor.id do
        Mix.raise(
          "production seed #{seed.id} belongs to #{seed.module_id}, but provider " <>
            "#{inspect(provider)} is installed as #{descriptor.id}"
        )
      end
    end)

    seeds
  end
end
