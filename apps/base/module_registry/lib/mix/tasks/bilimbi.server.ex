defmodule Mix.Tasks.Bilimbi.Server do
  @moduledoc """
  Starts the Bilimbi Phoenix server after validating workspace-graph metadata.

  A stale graph is repaired before Phoenix starts. Other compilation and
  application-start errors are left unchanged so this task does not hide
  unrelated failures.

  In development the database is brought up to date first: the task runs
  `mix bilimbi.migrate`, the one Bilimbi migration path, before `phx.server`,
  so a module migration that arrived with a pull is applied before the first
  request. A refusal (an unadopted Belimbing database, an invalid ledger, a
  failing migration) stops the task with that message and Phoenix does not
  start. Once Phoenix is up the task runs `mix bilimbi.dev.seed --at-startup`
  in the same VM: reference data is seeded through the production-seed
  ledger, a database with no development identity gets one, and a database
  whose identities carry no bootstrap receipt is reported in one line and
  left alone. The seed runs after `phx.server` because that task is what
  starts the application; a seed failure still stops the server with its
  message. Pass `--no-migrate` to skip both steps, for example to see the
  pending-migrations page (`BilimbiWeb.CheckPendingMigrations`) on purpose.
  Any other environment never migrates or seeds here: production uses its
  release commands.

  Remaining arguments go to `phx.server`.
  """

  use Mix.Task

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @shortdoc "Starts Phoenix with workspace-graph recovery"

  @no_migrate "--no-migrate"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    case graph_status() do
      :ok ->
        :ok

      {:stale, issues} ->
        Mix.shell().info("Workspace graph metadata is stale; rebuilding dependencies.")
        Mix.shell().info(format_issues(issues))

        Mix.Task.run("clean", ["--deps"])
        Mix.Task.Compiler.reenable()
        Mix.Task.run("compile")

        case graph_status() do
          :ok -> :ok
          {:stale, retry_issues} -> Mix.raise(rebuild_failure_message(retry_issues))
        end
    end

    start(args, Mix.env())
  end

  @doc """
  Migrates when `env` is `:dev` and `args` does not carry `--no-migrate`,
  starts Phoenix with the remaining arguments, then seeds the development
  database under the same condition. `run/1` calls this after the graph is
  known to be fresh; it is public so the start sequence can be exercised
  without compiling or repairing the workspace.
  """
  @spec start([String.t()], atom()) :: term()
  def start(args, env) do
    {skip, server_args} = Enum.split_with(args, &(&1 == @no_migrate))
    prepare? = env == :dev and skip == []

    if prepare? do
      Mix.shell().info("Migrating the development database before starting Phoenix.")
      Mix.Task.run("bilimbi.migrate")
    end

    Mix.Task.run("phx.server", server_args)

    if prepare?, do: Mix.Task.run("bilimbi.dev.seed", ["--at-startup"])
  end

  @doc false
  @spec graph_status(keyword()) :: :ok | {:stale, [tuple()]}
  def graph_status(options \\ []) do
    workspace_root =
      Keyword.get_lazy(options, :workspace_root, fn ->
        MixDiscovery.workspace_root!(File.cwd!())
      end)

    build_path = Keyword.get(options, :build_path, Mix.Project.build_path())
    expected_fingerprint = MixDiscovery.workspace_fingerprint(workspace_root)

    issues =
      workspace_root
      |> MixDiscovery.discover_workspace!()
      |> Enum.with_index()
      |> Enum.flat_map(fn {module, order} ->
        app_path = Path.join([build_path, "lib", Atom.to_string(module.otp_app), "ebin"])
        app_file = Path.join(app_path, Atom.to_string(module.otp_app) <> ".app")

        case read_descriptor(app_file) do
          {:ok, descriptor} ->
            descriptor_issues(descriptor, module, order, expected_fingerprint)

          {:error, reason} ->
            [{module.id, reason}]
        end
      end)

    if issues == [], do: :ok, else: {:stale, issues}
  end

  defp read_descriptor(app_file) do
    with true <- File.regular?(app_file),
         {:ok, [{:application, _app, properties}]} <-
           :file.consult(String.to_charlist(app_file)),
         {:ok, environment} <- Keyword.fetch(properties, :env),
         {:ok, descriptor} <- Keyword.fetch(environment, :bilimbi_module) do
      {:ok, descriptor}
    else
      false -> {:error, :missing_application_metadata}
      {:error, :enoent} -> {:error, :missing_application_metadata}
      {:error, reason} -> {:error, {:invalid_application_metadata, reason}}
      _other -> {:error, :invalid_application_metadata}
    end
  end

  defp descriptor_issues(descriptor, module, order, expected_fingerprint) do
    []
    |> maybe_add(descriptor[:graph_fingerprint] != expected_fingerprint, {
      module.id,
      {:fingerprint, descriptor[:graph_fingerprint], expected_fingerprint}
    })
    |> maybe_add(descriptor[:order] != order, {module.id, {:order, descriptor[:order], order}})
  end

  defp maybe_add(issues, false, _issue), do: issues
  defp maybe_add(issues, true, issue), do: [issue | issues]

  defp format_issues(issues) do
    details =
      Enum.map_join(issues, ", ", fn {module, reason} -> "#{module}: #{inspect(reason)}" end)

    "Detected #{length(issues)} graph metadata issue(s): #{details}"
  end

  defp rebuild_failure_message(issues) do
    "workspace graph metadata remains stale after rebuilding: #{format_issues(issues)}"
  end
end
