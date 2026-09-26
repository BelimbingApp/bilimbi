defmodule BilimbiWeb.Release do
  @moduledoc """
  Database commands for the `bilimbi` release, which has no Mix.

      bin/bilimbi eval "BilimbiWeb.Release.migrate()"
      bin/bilimbi eval "BilimbiWeb.Release.seed()"

  They do what `mix bilimbi.migrate` and `mix bilimbi.seeds.run` do from the
  umbrella root. Each first loads the host's whole application closure and
  refuses to run unless it contains every module of the discovered graph.
  """

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo

  @app :web

  @doc "Runs every pending installed migration through the shared ledger."
  @spec migrate() :: :ok
  def migrate do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()

    {:ok, _result, _started} =
      Ecto.Migrator.with_repo(Repo, &Bilimbi.Core.Compatibility.migrate(&1, []))

    :ok
  end

  @doc """
  Starts the module applications, without the endpoint and with job
  processing and the scheduler disabled, and runs every pending installed
  production seed, so it can run beside a live node.
  """
  @spec seed() :: :ok
  def seed do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()
    Application.put_env(:bilimbi_base_queue, :queues, [])
    Application.put_env(:bilimbi_base_queue, :plugins, [])
    Application.put_env(:bilimbi_base_schedule, :scheduler_enabled, false)
    {:ok, _started} = Application.ensure_all_started(dependencies(@app))
    ContributionRegistry.install!()

    case Database.run_production_seeds(Database.installed_production_seeds!()) do
      {:ok, results} ->
        Enum.each(results, &IO.puts("#{&1.status}: #{&1.id}"))

      {:error, failure} ->
        raise "production seed #{failure.seed_id} failed: #{inspect(failure.reason)}"
    end
  end

  # `eval` starts a clean node: loading an application does not load its
  # dependencies, so walk the closure. An optional dependency may be absent.
  defp load_closure!(app, loaded \\ MapSet.new()) do
    if MapSet.member?(loaded, app) do
      loaded
    else
      load!(app)

      app
      |> dependencies()
      |> Enum.reduce(MapSet.put(loaded, app), &load_closure!/2)
    end
  end

  defp dependencies(app) do
    optional = Application.spec(app, :optional_applications) || []

    (List.wrap(Application.spec(app, :applications)) ++
       List.wrap(Application.spec(app, :included_applications)))
    |> Enum.reject(&(&1 in optional and not loadable?(&1)))
  end

  defp load!(app) do
    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
      {:error, reason} -> raise "could not load #{app}: #{inspect(reason)}"
    end
  end

  defp loadable?(app), do: :code.where_is_file(~c"#{app}.app") != :non_existing
end
