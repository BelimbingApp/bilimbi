defmodule Mix.Tasks.Bilimbi.Server do
  @moduledoc """
  Starts the Bilimbi Phoenix server after validating workspace-graph metadata.

  A stale graph is repaired before Phoenix starts. Other compilation and
  application-start errors are left unchanged so this task does not hide
  unrelated failures.
  """

  use Mix.Task

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @shortdoc "Starts Phoenix with workspace-graph recovery"

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

    Mix.Task.run("phx.server", args)
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
