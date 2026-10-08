defmodule BilimbiWeb.Release do
  @moduledoc """
  Database and initial setup commands for the `bilimbi` release, which has no Mix.

      bin/bilimbi eval "BilimbiWeb.Release.migrate()"
      bin/bilimbi eval "BilimbiWeb.Release.seed()"
      bin/bilimbi eval "BilimbiWeb.Release.bootstrap()"
      bin/bilimbi eval "BilimbiWeb.Release.verify()"
      bin/bilimbi eval "BilimbiWeb.Release.adopt()"
      bin/bilimbi eval "BilimbiWeb.Release.remap_dry_run()"
      bin/bilimbi eval "BilimbiWeb.Release.remap()"

  Migration, seeding, verification, adoption and remapping mirror their
  umbrella Mix commands. An existing Belimbing database takes them in the
  order verify, adopt, remap_dry_run, remap, migrate, seed; `migrate` refuses
  an unadopted Belimbing database, so a deployment cannot skip the first four.
  Bootstrap seeds reference data and calls Core User's one-time installation
  API. Each loads the host's whole application closure and refuses an
  incomplete discovered graph before touching the database.
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
      Ecto.Migrator.with_repo(Repo, fn repo ->
        :ok = Bilimbi.Core.Compatibility.ensure_adopted!(repo, [])
        Bilimbi.Core.Compatibility.migrate(repo, [])
      end)

    :ok
  end

  @doc """
  Read-only check of every installed schema contract and live-data invariant.
  Raises, naming each drift, when the schema is not compatible.
  """
  @spec verify() :: :ok
  def verify do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()

    {:ok, result, _started} =
      Ecto.Migrator.with_repo(Repo, fn repo ->
        with :ok <- Bilimbi.Core.Compatibility.verify(repo, []) do
          {:ok, Bilimbi.Core.Compatibility.absent_module_report(repo, [])}
        end
      end)

    case result do
      {:ok, absent} ->
        IO.puts("Bilimbi compatibility schema verified.")
        Enum.each(absent, &IO.puts/1)

      {:error, errors} ->
        raise "Bilimbi compatibility schema drift detected:\n" <>
                Enum.map_join(errors, "\n", &"  - #{&1}")
    end

    :ok
  end

  @doc "Reports the cutover remap without writing; run it before `remap/0`."
  @spec remap_dry_run() :: :ok
  def remap_dry_run, do: remap_values(true)

  @doc """
  Remaps Belimbing stored values Bilimbi interprets differently. Run once
  after `adopt/0`; it is idempotent.
  """
  @spec remap() :: :ok
  def remap, do: remap_values(false)

  defp remap_values(dry_run?) do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()
    ContributionRegistry.install!()

    {:ok, result, _started} =
      Ecto.Migrator.with_repo(Repo, fn repo ->
        Bilimbi.Core.Compatibility.Cutover.run(repo: repo, dry_run: dry_run?)
      end)

    case result do
      {:ok, report} ->
        report |> Bilimbi.Core.Compatibility.Cutover.report_lines() |> Enum.each(&IO.puts/1)

      {:error, message} ->
        raise "cutover remap failed: #{message}"
    end

    :ok
  end

  @doc """
  Starts the module applications, without the endpoint and with job
  processing and the scheduler disabled, and runs every pending installed
  production seed, so it can run beside a live node.
  """
  @spec seed() :: :ok
  def seed do
    start_without_workers()

    case Database.run_production_seeds(Database.installed_production_seeds!()) do
      {:ok, results} ->
        Enum.each(results, &IO.puts("#{&1.status}: #{&1.id}"))

      {:error, failure} ->
        raise "production seed #{failure.seed_id} failed: #{inspect(failure.reason)}"
    end
  end

  @doc "Verifies and explicitly adopts an existing Belimbing schema before migration."
  @spec adopt() :: :ok
  def adopt do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()

    {:ok, result, _started} =
      Ecto.Migrator.with_repo(Repo, fn repo ->
        with {:ok, status} <- Bilimbi.Core.Compatibility.adopt(repo, []) do
          {:ok, status, Bilimbi.Core.Compatibility.absent_module_report(repo, [])}
        end
      end)

    case result do
      {:ok, status, absent} ->
        IO.puts("Schema #{status}")
        Enum.each(absent, &IO.puts/1)

      {:error, reason} ->
        raise "schema adoption refused: #{inspect(reason)}"
    end

    :ok
  end

  @doc """
  Runs reference seeds and the one-time initial-administrator bootstrap.

  Identity comes from BOOT_TENANT_NAME, BOOT_COMPANY_NAME, BOOT_COMPANY_CODE,
  BOOT_ADMIN_NAME and BOOT_ADMIN_EMAIL. Read the password from stdin, never
  command arguments or the persistent environment file. A blank line is valid
  on a completed repeat. This command has no HTTP entry point.
  """
  @spec bootstrap() :: :ok
  def bootstrap do
    attributes = %{
      tenant_name: System.fetch_env!("BOOT_TENANT_NAME"),
      company_name: System.fetch_env!("BOOT_COMPANY_NAME"),
      company_code: System.fetch_env!("BOOT_COMPANY_CODE"),
      admin_name: System.fetch_env!("BOOT_ADMIN_NAME"),
      admin_email: System.fetch_env!("BOOT_ADMIN_EMAIL"),
      password: bootstrap_password()
    }

    seed()

    case Bilimbi.Core.User.bootstrap_platform_admin(attributes) do
      {:ok, status} -> IO.puts("Administrator bootstrap: #{status}")
      {:error, reason} -> raise "administrator bootstrap refused: #{bootstrap_failure(reason)}"
    end

    :ok
  end

  defp bootstrap_password do
    case IO.read(:stdio, :line) do
      line when is_binary(line) ->
        line |> String.trim_trailing("\n") |> String.trim_trailing("\r")

      _eof_or_error ->
        nil
    end
  end

  defp bootstrap_failure(:existing_users),
    do: "accounts already exist; use adopt/upgrade and existing administrator recovery"

  defp bootstrap_failure(:existing_platform_operator),
    do: "a platform operator already exists without a bootstrap receipt; use adopt/upgrade"

  defp bootstrap_failure(:bootstrap_identity_conflict),
    do:
      "setup already completed for another identity; repeat the original identity or use upgrade"

  defp bootstrap_failure(:password_required), do: "provide a password for initial setup"

  defp bootstrap_failure(:system_roles_missing),
    do: "system roles are missing; explicitly reconcile system roles before repeating setup"

  defp bootstrap_failure(:invalid_bootstrap_attributes),
    do: "check tenant/company names, company code, administrator name/email and password"

  defp bootstrap_failure(reason), do: Atom.to_string(reason)

  @doc """
  Starts the module applications without the endpoint, job processing, or
  the scheduler, so a one-off `eval` can call module APIs beside a live node.
  """
  @spec start_without_workers() :: :ok
  def start_without_workers do
    load_closure!(@app)
    ModuleRegistry.complete_modules!()
    disable_workers()
    {:ok, _started} = Application.ensure_all_started(seed_applications())
    ContributionRegistry.install!()
    :ok
  end

  @doc false
  # Oban keeps a configured value only when it is truthy, so empty lists, not
  # `false`, disable its queues and plugins.
  @spec disable_workers() :: :ok
  def disable_workers do
    Application.put_env(:bilimbi_base_queue, :queues, [])
    Application.put_env(:bilimbi_base_queue, :plugins, [])
    Application.put_env(:bilimbi_base_schedule, :scheduler_enabled, false)
  end

  @doc false
  # The host's dependencies without the host itself, which owns the endpoint.
  @spec seed_applications() :: [atom()]
  def seed_applications, do: dependencies(@app)

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
