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
    uri = URI.parse(endpoint)

    unless uri.scheme == "https" and is_binary(uri.host),
      do: Mix.raise("Configure the host's public HTTPS URL before exporting a ChatGPT plugin")

    unless Map.has_key?(Bilimbi.Base.Settings.get("agent_access.oauth_clients"), opts[:client]),
      do: Mix.raise("Register this public OAuth client in Global Settings first")

    output = Path.expand(opts[:output])

    if File.exists?(output),
      do: Mix.raise("Output directory already exists; choose a new directory")

    source = Path.expand("../../../../../plugins/bilimbi", __DIR__)
    manifest = source |> Path.join("plugin.json") |> File.read!() |> Jason.decode!()
    File.mkdir_p!(output)
    write(output, "plugin.json", manifest)

    write(output, "mcp.json", %{
      "$schema" => "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
      "mcpServers" => %{
        "bilimbi" => %{
          "type" => "streamable-http",
          "url" => endpoint <> "/mcp",
          "extensions" => %{
            "com.openai" => %{
              "auth" => %{
                "type" => "oauth",
                "client" => %{
                  "mode" => "provided",
                  "clientId" => opts[:client],
                  "tokenEndpointAuthMethod" => "none"
                },
                "authorizationUrl" => endpoint <> "/oauth/authorize",
                "tokenUrl" => endpoint <> "/oauth/token",
                "baseScopes" => ["bilimbi"]
              }
            }
          }
        }
      }
    })

    File.cp_r!(Path.join(source, "skills"), Path.join(output, "skills"))

    Mix.shell().info(
      "Exported #{output}. Connect #{endpoint}/mcp in ChatGPT using client #{opts[:client]} and OAuth without a client secret."
    )
  end

  defp write(output, name, value),
    do: File.write!(Path.join(output, name), Jason.encode!(value, pretty: true) <> "\n")
end
