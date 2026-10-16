defmodule BilimbiWeb.MCPTest do
  # Drives the node-wide MCP rate-limit ETS bucket.
  use BilimbiWeb.ConnCase, async: false
  alias Bilimbi.Base.{AgentApi, Authz, Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.{AgentAccess, Company}

  setup do
    signed_in_identity!()
    AgentAccess.TestFixtures.create_tables!()
    AgentApi.TestFixtures.create_plan_tables!()
    Bilimbi.Base.Integration.TestFixtures.create_exchanges_table!()

    grant_capabilities!(
      ~w(admin.company.list admin.company.view admin.company.create admin.company.tenant-wide.manage)
    )

    {:ok, tenant} = Tenancy.scope(41)
    scope = Authentication.sign_in(tenant, 91, 73)

    {:ok, _} =
      Settings.put("agent_access.oauth_clients", %{
        "test-mcp" => %{"name" => "Test MCP", "redirect_uris" => ["https://client.test/callback"]}
      })

    verifier = String.duplicate("a", 43)

    params = %{
      "client_id" => "test-mcp",
      "redirect_uri" => "https://client.test/callback",
      "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256",
      "response_type" => "code",
      "scope" => "bilimbi",
      "resource" => BilimbiWeb.MCPController.resource()
    }

    {:ok, code} =
      AgentAccess.authorize(
        scope,
        params,
        params["resource"],
        DateTime.add(DateTime.utc_now(), 3600)
      )

    {:ok, tokens} =
      AgentAccess.exchange_code(
        Map.merge(params, %{"code" => code, "code_verifier" => verifier}),
        params["resource"]
      )

    %{scope: scope, tokens: tokens}
  end

  defp rpc(conn, method, params \\ %{}, token \\ nil) do
    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-protocol-version", "2025-11-25")
      |> put_req_header("x-bilimbi-run-id", "mcp-test")

    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    post(conn, "/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})
  end

  defp call(conn, name, args, token),
    do:
      rpc(conn, "tools/call", %{"name" => name, "arguments" => args}, token)
      |> json_response(200)
      |> Map.fetch!("result")

  test "public discovery and private authentication challenge", %{conn: conn} do
    assert rpc(conn, "tools/list")
           |> json_response(200)
           |> get_in(["result", "tools"])
           |> length() == 6

    tools =
      for meta <- [%{}, %{"progressToken" => 17}] do
        rpc(conn, "tools/list", %{"_meta" => meta})
        |> json_response(200)
        |> get_in(["result", "tools"])
      end

    assert [first, second] = tools
    assert first == second
    assert length(first) == 6

    refused =
      rpc(conn, "tools/call", %{"name" => "search", "arguments" => %{"query" => "company"}})

    assert json_response(refused, 401)["error"] == "invalid_token"

    assert get_resp_header(refused, "www-authenticate") == [
             ~s(Bearer resource_metadata="#{BilimbiWeb.Endpoint.url()}/.well-known/oauth-protected-resource/mcp")
           ]

    rows = Repo.all(Bilimbi.Base.Integration.Exchange)
    assert Enum.all?(rows, &(is_nil(&1.request_body) and is_nil(&1.response_body)))
    assert Enum.any?(rows, &(&1.response_status == 401))
  end

  test "reads reuse scoped discovery and refuse writes and another tenant", %{
    conn: conn,
    tokens: tokens
  } do
    token = tokens.access_token
    found = call(conn, "search", %{"query" => "companies"}, token)
    refute found["isError"]
    assert Enum.any?(found["structuredContent"]["result"], &(&1["key"] == "core.company.list"))

    assert call(conn, "describe", %{"key" => "core.company.list"}, token)["structuredContent"][
             "kind"
           ] == "read"

    result =
      call(conn, "read", %{"key" => "core.company.get", "input" => %{"company_id" => 73}}, token)

    assert result["structuredContent"]["result"]["id"] == 73

    denied =
      call(
        conn,
        "read",
        %{"key" => "core.company.create", "input" => %{"name" => "Cannot call writes"}},
        token
      )

    assert denied["isError"]
    assert denied["structuredContent"]["error"] == "writes_not_enabled"
    Bilimbi.Core.Company.TestFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})

    Bilimbi.Core.Company.TestFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      code: "other_tenant"
    })

    assert call(
             conn,
             "read",
             %{"key" => "core.company.get", "input" => %{"company_id" => 74}},
             token
           )["structuredContent"]["error"] == "not_found"
  end

  test "preview changes nothing and exact reviewed input commits once with verification links", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    operations = [%{"key" => "core.company.create", "input" => %{"name" => "MCP supplier"}}]
    before = Repo.aggregate(Bilimbi.Core.Company.Schema, :count)

    plan =
      call(conn, "plan", %{"operations" => operations}, tokens.access_token)["structuredContent"]

    assert plan["valid"]
    assert plan["results"] != []
    assert Repo.aggregate(Bilimbi.Core.Company.Schema, :count) == before
    args = %{"plan_code" => plan["plan_code"], "operations" => operations}
    report = call(conn, "commit", args, tokens.access_token)
    refute report["isError"]
    [created] = report["structuredContent"]["results"]
    assert created["url"] == BilimbiWeb.Endpoint.url() <> created["path"]
    assert {:ok, %{name: "MCP supplier"}} = Company.get_company(scope, created["record"]["id"])

    assert call(conn, "commit", args, tokens.access_token)["structuredContent"]["error"] ==
             "plan_already_used"
  end

  test "field restrictions and revoked grants apply on each MCP call", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    grant_capabilities!("admin.authz.field.manage")
    {:ok, role} = Authz.create_role(scope, 73, %{name: "Restricted", code: "restricted"})
    {:ok, _} = Authz.put_field_restriction(scope, "companies", "jurisdiction", [role.id])
    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    result =
      call(
        conn,
        "read",
        %{"key" => "core.company.get", "input" => %{"company_id" => 73}},
        tokens.access_token
      )

    assert result["structuredContent"]["result"]["jurisdiction"] == %{"restricted" => true}
    {:ok, [connection]} = AgentAccess.list_connections(scope)
    assert :ok = AgentAccess.revoke(scope, connection.id)

    assert rpc(
             conn,
             "tools/call",
             %{"name" => "search", "arguments" => %{"query" => "company"}},
             tokens.access_token
           )
           |> json_response(401)
           |> Map.fetch!("error") == "invalid_token"
  end

  test "transport rejects bad origins and versions, accepts notifications, and offers no SSE", %{
    conn: conn
  } do
    for version <- Bilimbi.Base.AgentApi.MCP.versions() do
      initialized =
        conn
        |> recycle()
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-protocol-version", version)
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => version,
            "capabilities" => %{},
            "clientInfo" => %{"name" => "test", "version" => "1"}
          }
        })

      assert json_response(initialized, 200)["result"]["protocolVersion"] == version
    end

    assert conn
           |> put_req_header("origin", "https://attacker.test")
           |> put_req_header("accept", "application/json, text/event-stream")
           |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})
           |> json_response(403) == %{"error" => "invalid_origin"}

    assert conn
           |> recycle()
           |> put_req_header("mcp-protocol-version", "wrong")
           |> post("/mcp", %{})
           |> json_response(400) == %{"error" => "unsupported_protocol_version"}

    assert conn
           |> recycle()
           |> put_req_header("mcp-protocol-version", "2025-03-26")
           |> post("/mcp", %{})
           |> json_response(400) == %{"error" => "unsupported_protocol_version"}

    notification =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert response(notification, 202) == ""
    assert response(get(recycle(conn), "/mcp"), 405) == ""
  end
end
