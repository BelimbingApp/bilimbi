defmodule Bilimbi.Core.AgentAccess.Web.PluginLiveTest do
  # Changes the node-shared Endpoint URL to exercise installation-specific packages.
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.AgentAccess

  setup %{conn: conn} do
    signed_in_identity!()
    original = Application.fetch_env!(:web, BilimbiWeb.Endpoint)

    updated =
      Keyword.put(original, :url, scheme: "https", host: "company.bilimbi.test", port: 443)

    BilimbiWeb.Endpoint.config_change([{BilimbiWeb.Endpoint, updated}], [])
    on_exit(fn -> BilimbiWeb.Endpoint.config_change([{BilimbiWeb.Endpoint, original}], []) end)
    {:ok, tenant} = Tenancy.scope(41)
    %{conn: log_in_as(conn), scope: Authentication.sign_in(tenant, 91, 73)}
  end

  defp register(id \\ "chatgpt-company") do
    {:ok, _} =
      Settings.put("agent_access.oauth_clients", %{
        id => %{"name" => "Company ChatGPT", "redirect_uris" => ["https://client.test/callback"]}
      })
  end

  test "settings lead to setup and the page explains both network paths", %{conn: conn} do
    register()
    {:ok, profile, _} = live(conn, "/settings/profile")
    assert has_element?(profile, "#settings-chatgpt-plugin[href='/settings/chatgpt-plugin']")
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "h1", "Plugin for ChatGPT")
    assert has_element?(view, "#chatgpt-install")

    assert has_element?(
             view,
             "#chatgpt-public-guide[href='https://developers.openai.com/plugins/deploy/connect-chatgpt']"
           )

    assert has_element?(
             view,
             "#chatgpt-private-guide[href='https://developers.openai.com/api/docs/guides/secure-mcp-tunnels']"
           )

    assert has_element?(view, "#chatgpt-server-url", "https://company.bilimbi.test/mcp")

    assert has_element?(
             view,
             "#chatgpt-copy-server[data-copy-text='https://company.bilimbi.test/mcp']"
           )

    assert has_element?(view, "#chatgpt-client-id", "chatgpt-company")
    assert has_element?(view, "#chatgpt-download")
    assert has_element?(view, "#chatgpt-connections[href='/settings/agent-connections']")
  end

  test "missing registration explains why there is no download", %{conn: conn} do
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "#chatgpt-no-clients")
    refute has_element?(view, "#chatgpt-download")
    assert conn |> get("/settings/chatgpt-plugin/download?client_id=unknown") |> response(404)
  end

  test "a choice is required for multiple clients and the selected ID survives in the URL", %{
    conn: conn
  } do
    client = %{"name" => "ChatGPT", "redirect_uris" => ["https://client.test/callback"]}

    {:ok, _} =
      Settings.put("agent_access.oauth_clients", %{"first" => client, "second" => client})

    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "#chatgpt-client-required")
    refute has_element?(view, "#chatgpt-download")
    view |> form("#chatgpt-client-form", connection: %{client_id: "second"}) |> render_change()
    assert_patch(view, "/settings/chatgpt-plugin?client_id=second")

    assert has_element?(
             view,
             "#chatgpt-download[href='/settings/chatgpt-plugin/download?client_id=second']"
           )

    assert has_element?(view, "#chatgpt-client-id", "second")
  end

  test "only a real browser copy result reports success", %{conn: conn} do
    register()
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    refute has_element?(view, "#chatgpt-copy-success")

    render_hook(view, "connection_copied", %{
      text: "https://company.bilimbi.test/mcp",
      copied: false
    })

    assert has_element?(view, "#chatgpt-copy-failed")

    render_hook(view, "connection_copied", %{
      text: "https://company.bilimbi.test/mcp",
      copied: true
    })

    assert has_element?(view, "#chatgpt-copy-success")
  end

  test "the ZIP contains portable skills and only this installation's public configuration", %{
    conn: conn
  } do
    register()

    download =
      %{conn | host: "attacker.test"}
      |> get("/settings/chatgpt-plugin/download?client_id=chatgpt-company")

    assert get_resp_header(download, "cache-control") == ["private, no-store"]
    assert get_resp_header(download, "content-type") == ["application/zip"]
    {:ok, entries} = :zip.extract(response(download, 200), [:memory])
    files = Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)

    assert Enum.sort(Map.keys(files)) == [
             "bilimbi/mcp.json",
             "bilimbi/plugin.json",
             "bilimbi/skills/bilimbi/SKILL.md",
             "bilimbi/skills/setup/SKILL.md"
           ]

    server = Jason.decode!(files["bilimbi/mcp.json"])["mcpServers"]["bilimbi"]
    assert server["url"] == "https://company.bilimbi.test/mcp"
    auth = server["extensions"]["com.openai"]["auth"]
    assert auth["client"]["clientId"] == "chatgpt-company"
    assert auth["client"]["tokenEndpointAuthMethod"] == "none"
    refute Map.has_key?(auth, "clientSecret")
    manifest = Jason.decode!(files["bilimbi/plugin.json"])
    setup = manifest["extensions"]["com.openai"]["onboardingSkill"]
    assert Map.has_key?(files, "bilimbi/" <> String.trim_leading(setup, "./"))
  end

  test "a removed client is refused even if its old page still shows a download", %{conn: conn} do
    register()
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "#chatgpt-download")
    {:ok, _} = Settings.put("agent_access.oauth_clients", %{})

    assert conn
           |> get("/settings/chatgpt-plugin/download?client_id=chatgpt-company")
           |> response(404)
  end

  test "HTTP configuration withholds the download and direct requests are refused", %{conn: conn} do
    register()
    config = Application.fetch_env!(:web, BilimbiWeb.Endpoint)
    config = Keyword.put(config, :url, scheme: "http", host: "local.test", port: 80)
    BilimbiWeb.Endpoint.config_change([{BilimbiWeb.Endpoint, config}], [])
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "#chatgpt-https-required")
    refute has_element?(view, "#chatgpt-download")

    assert conn
           |> get("/settings/chatgpt-plugin/download?client_id=chatgpt-company")
           |> response(409)
  end

  test "impersonation cannot prepare or download a personal connection", %{
    conn: conn,
    scope: scope
  } do
    register()
    conn = impersonating_as(conn, 92, "Operator")
    {:ok, view, _} = live(conn, "/settings/chatgpt-plugin")
    assert has_element?(view, "#chatgpt-person-required")
    refute has_element?(view, "#chatgpt-setup")

    assert conn
           |> get("/settings/chatgpt-plugin/download?client_id=chatgpt-company")
           |> response(403)

    {:ok, tenant} = Tenancy.scope(41)

    agent =
      Authentication.sign_in(tenant, 91, 73,
        agent: %{type: :agent, connection_id: 1, agent_id: "test/agent"}
      )

    assert {:error, :person_required} = AgentAccess.plugin_clients(agent)

    assert {:error, :person_required} =
             AgentAccess.plugin_download(agent, "https://company.bilimbi.test", "chatgpt-company")

    assert {:ok, [_]} = AgentAccess.plugin_clients(scope)
  end

  test "anonymous users must sign in before viewing or downloading" do
    for path <- [
          "/settings/chatgpt-plugin",
          "/settings/chatgpt-plugin/download?client_id=chatgpt-company"
        ] do
      assert build_conn() |> get(path) |> redirected_to() == "/"
    end
  end
end
