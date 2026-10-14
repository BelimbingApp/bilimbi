defmodule BilimbiWeb.MCPController do
  @moduledoc "Stateless Streamable HTTP: JSON replies, no SSE or session store. All private calls use the existing bearer edge."
  use BilimbiWeb, :controller
  alias Bilimbi.Base.AgentApi.MCP

  def resource, do: BilimbiWeb.Endpoint.url() <> "/mcp"

  def handle(conn, message) do
    cond do
      not valid_origin?(conn) ->
        conn |> put_status(403) |> json(%{error: "invalid_origin"})

      not valid_version?(conn) ->
        conn |> put_status(400) |> json(%{error: "unsupported_protocol_version"})

      conn.method != "POST" ->
        conn |> put_resp_header("allow", "POST") |> send_resp(405, "")

      not acceptable?(conn) ->
        send_resp(conn, 406, "")

      not allowed?(conn) ->
        conn |> put_resp_header("retry-after", "60") |> send_resp(429, "")

      true ->
        dispatch(conn, message)
    end
  end

  defp dispatch(conn, message) do
    conn =
      if MCP.public?(message),
        do: conn,
        else: BilimbiWeb.AgentAuth.call(conn, audience: :mcp)

    if conn.halted do
      conn
    else
      conn = assign(conn, :agent_operation, operation(message))

      case MCP.dispatch(conn.assigns[:agent_scope], message) do
        :accepted -> send_resp(conn, 202, "")
        {:reply, reply} -> json(conn, record_urls(reply))
      end
    end
  end

  defp operation(%{"method" => "tools/call", "params" => %{"name" => name}}) when is_binary(name),
    do: "mcp." <> name

  defp operation(%{"method" => method}) when is_binary(method), do: "mcp." <> method
  defp operation(_), do: "mcp.invalid_request"

  # Absolute result links belong to the host. Domain operations return paths.
  defp record_urls(
         %{result: %{structuredContent: %{"results" => results} = content} = result} = reply
       ) do
    results =
      Enum.map(results, fn
        %{"path" => path} = item -> Map.put(item, "url", BilimbiWeb.Endpoint.url() <> path)
        item -> item
      end)

    content = Map.put(content, "results", results)

    %{
      reply
      | result: %{
          result
          | structuredContent: content,
            content: [%{type: "text", text: Jason.encode!(content)}]
        }
    }
  end

  defp record_urls(reply), do: reply

  defp valid_origin?(conn),
    do: get_req_header(conn, "origin") in [[], [BilimbiWeb.Endpoint.url()]]

  defp valid_version?(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> true
      [version] -> version in MCP.versions()
      _ -> false
    end
  end

  defp acceptable?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(",")
    String.contains?(accept, "application/json") and String.contains?(accept, "text/event-stream")
  end

  defp allowed?(conn) do
    key = {:mcp, conn.remote_ip}

    case BilimbiWeb.RateLimit.attempt_allowed?(
           key,
           Bilimbi.Base.Settings.get("agent_api.mcp_requests_per_minute")
         ) do
      :allow ->
        BilimbiWeb.RateLimit.record_attempt(key)
        true

      _ ->
        false
    end
  end
end
