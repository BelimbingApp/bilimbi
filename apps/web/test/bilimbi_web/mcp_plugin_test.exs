defmodule BilimbiWeb.MCPPluginTest do
  # Changes the shared Endpoint configuration and runs a Mix task.
  use BilimbiWeb.ConnCase, async: false
  alias Bilimbi.Base.Settings

  test "export resolves the registered client, packaged skills and this installation's HTTPS origin" do
    original = Application.fetch_env!(:web, BilimbiWeb.Endpoint)
    updated = Keyword.put(original, :url, scheme: "https", host: "bilimbi.example", port: 443)
    BilimbiWeb.Endpoint.config_change([{BilimbiWeb.Endpoint, updated}], [])
    on_exit(fn -> BilimbiWeb.Endpoint.config_change([{BilimbiWeb.Endpoint, original}], []) end)

    {:ok, _} =
      Settings.put("agent_access.oauth_clients", %{
        "export-client" => %{
          "name" => "ChatGPT",
          "redirect_uris" => ["https://client.test/callback"]
        }
      })

    output =
      Path.join(System.tmp_dir!(), "bilimbi-mcp-export-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(output) end)
    Mix.Tasks.Bilimbi.Mcp.Plugin.run(["--client", "export-client", "--output", output])
    config = Path.join(output, "mcp.json") |> File.read!() |> Jason.decode!()
    server = config["mcpServers"]["bilimbi"]
    assert server["type"] == "streamable-http"
    assert server["url"] == "https://bilimbi.example/mcp"
    assert server["extensions"]["com.openai"]["auth"]["client"]["clientId"] == "export-client"

    assert server["extensions"]["com.openai"]["auth"]["client"]["tokenEndpointAuthMethod"] ==
             "none"

    manifest = Path.join(output, "plugin.json") |> File.read!() |> Jason.decode!()
    setup = manifest["extensions"]["com.openai"]["onboardingSkill"]
    assert File.regular?(Path.join(output, setup))
    assert File.regular?(Path.join(output, "skills/bilimbi/SKILL.md"))
    refute File.exists?(Path.join(output, "bin"))

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Bilimbi.Mcp.Plugin.run(["--client", "export-client", "--output", output])
    end

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Bilimbi.Mcp.Plugin.run(["--client", "missing", "--output", output <> "-missing"])
    end
  end

  test "HTTP origins cannot be exported" do
    assert_raise Mix.Error, ~r/HTTPS/, fn ->
      Mix.Tasks.Bilimbi.Mcp.Plugin.run(["--client", "test", "--output", "unused-http-output"])
    end
  end
end
