defmodule Bilimbi.Base.AgentApi.MCPTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.AgentApi.MCP

  test "initialization negotiates a supported version and generic tools declare auth and actual side effects" do
    assert {:reply, %{result: result}} =
             MCP.dispatch(nil, %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "initialize",
               "params" => %{
                 "protocolVersion" => "future",
                 "capabilities" => %{},
                 "clientInfo" => %{"name" => "test", "version" => "1"}
               }
             })

    assert result.protocolVersion in MCP.versions()
    assert result.capabilities == %{tools: %{listChanged: false}}

    assert {:reply, %{result: %{tools: tools}}} =
             MCP.dispatch(nil, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})

    assert Enum.map(tools, & &1.name) == ~w(search describe guide read plan commit)
    assert Enum.all?(tools, &(&1.securitySchemes == [%{type: "oauth2", scopes: ["bilimbi"]}]))
    assert Enum.find(tools, &(&1.name == "read")).annotations.readOnlyHint
    refute Enum.find(tools, &(&1.name == "plan")).annotations.readOnlyHint
    assert Enum.find(tools, &(&1.name == "commit")).annotations.destructiveHint

    for params <- [%{"_meta" => %{}}, %{"_meta" => %{"progressToken" => 7}}] do
      assert {:reply, %{result: %{tools: ^tools}}} =
               MCP.dispatch(nil, %{
                 "jsonrpc" => "2.0",
                 "id" => 3,
                 "method" => "tools/list",
                 "params" => params
               })
    end

    assert {:reply, %{error: %{code: -32_602, message: "Unsupported cursor"}}} =
             MCP.dispatch(nil, %{
               "jsonrpc" => "2.0",
               "id" => 4,
               "method" => "tools/list",
               "params" => %{"cursor" => "next"}
             })
  end

  test "notifications return no RPC reply and malformed messages and unknown methods fail" do
    assert :accepted =
             MCP.dispatch(nil, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    for message <- [
          %{},
          [],
          %{"jsonrpc" => "1.0", "id" => 1, "method" => "ping"},
          %{"jsonrpc" => "2.0", "method" => "tools/list"}
        ] do
      assert {:reply, %{error: %{code: -32_600}}} = MCP.dispatch(nil, message)
    end

    assert {:reply, %{error: %{code: -32_601}}} =
             MCP.dispatch(nil, %{"jsonrpc" => "2.0", "id" => 1, "method" => "unknown"})

    assert {:reply, %{error: %{code: -32_602}}} =
             MCP.dispatch(nil, %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "ping",
               "params" => []
             })
  end
end
