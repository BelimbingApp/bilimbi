defmodule Mix.Tasks.Bilimbi.Mcp.Plugin do
  @shortdoc "Export this installation's HTTPS MCP plugin"
  @moduledoc """
  mix bilimbi.mcp.plugin --client <registered-client-id> --output <new-directory>

  Exports the portable manifest, remote MCP OAuth configuration and skills for
  this installation. The endpoint comes from the host's configured public URL,
  never a template or a shared vendor server. Configure HTTPS and the OAuth
  client's exact callback addresses through Global Settings first. This writes
  a local package; it does not install, publish or register it with OpenAI.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [client: :string, output: :string])

    unless positional == [] and invalid == [] and is_binary(opts[:client]) and
             is_binary(opts[:output]),
           do: Mix.raise("Usage: mix bilimbi.mcp.plugin --client <id> --output <new-directory>")

    Mix.Task.run("app.start")
    endpoint = BilimbiWeb.Endpoint.url()

    files =
      case Bilimbi.Core.AgentAccess.plugin_files(endpoint, opts[:client]) do
        {:ok, files} ->
          files

        {:error, :https_required} ->
          Mix.raise("Configure the host's public HTTPS URL first")

        {:error, :invalid_client} ->
          Mix.raise("Register this public OAuth client in Global Settings first")
      end

    output = Path.expand(opts[:output])

    if File.exists?(output),
      do: Mix.raise("Output directory already exists; choose a new directory")

    for {path, bytes} <- files do
      target = Path.join(output, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, bytes)
    end

    Mix.shell().info(
      "Exported #{output}. Connect #{endpoint}/mcp in ChatGPT using client #{opts[:client]} and OAuth without a client secret."
    )
  end
end
