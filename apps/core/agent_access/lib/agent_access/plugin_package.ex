defmodule Bilimbi.Core.AgentAccess.PluginPackage do
  @moduledoc false

  # Compile the canonical plugin sources into the application. A release can
  # serve the same package as the Mix exporter without a source checkout,
  # runtime filesystem writes, credentials or native executables.
  @source Path.expand("../../../../../plugins/bilimbi", __DIR__)
  @files ~w(plugin.json skills/bilimbi/SKILL.md skills/setup/SKILL.md)
  for path <- @files do
    @external_resource Path.join(@source, path)
  end

  @templates Enum.map(@files, &{&1, File.read!(Path.join(@source, &1))})

  def clients do
    Bilimbi.Base.Settings.get("agent_access.oauth_clients")
    |> Enum.map(fn {id, client} -> %{id: id, name: client["name"]} end)
    |> Enum.sort_by(&{&1.name, &1.id})
  end

  def files(origin, client_id) do
    uri = URI.parse(origin)

    cond do
      uri.scheme != "https" or not is_binary(uri.host) or uri.host == "" or
        not is_nil(uri.userinfo) or not is_nil(uri.query) or not is_nil(uri.fragment) or
          uri.path not in [nil, "", "/"] ->
        {:error, :https_required}

      not Enum.any?(clients(), &(&1.id == client_id)) ->
        {:error, :invalid_client}

      true ->
        {:ok,
         @templates ++ [{"mcp.json", configuration(String.trim_trailing(origin, "/"), client_id)}]}
    end
  end

  def archive(origin, client_id) do
    with {:ok, files} <- files(origin, client_id) do
      entries =
        Enum.map(files, fn {path, bytes} -> {String.to_charlist("bilimbi/" <> path), bytes} end)

      case :zip.create(~c"bilimbi-chatgpt-plugin.zip", entries, [:memory]) do
        {:ok, {_name, bytes}} -> {:ok, bytes}
        {:error, _reason} -> {:error, :package_unavailable}
      end
    end
  end

  defp configuration(origin, client_id) do
    %{
      "$schema" => "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
      "mcpServers" => %{
        "bilimbi" => %{
          "type" => "streamable-http",
          "url" => origin <> "/mcp",
          "extensions" => %{
            "com.openai" => %{
              "auth" => %{
                "type" => "oauth",
                "client" => %{
                  "mode" => "provided",
                  "clientId" => client_id,
                  "tokenEndpointAuthMethod" => "none"
                },
                "authorizationUrl" => origin <> "/oauth/authorize",
                "tokenUrl" => origin <> "/oauth/token",
                "baseScopes" => ["bilimbi"]
              }
            }
          }
        }
      }
    }
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end
end
