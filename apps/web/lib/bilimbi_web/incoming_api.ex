defmodule BilimbiWeb.IncomingApi do
  @moduledoc """
  One general Integration measurement for API and OAuth requests, refusals
  included. Registered before negotiation and authentication; bodies, query
  strings, authorization headers and token values never enter the recorder.
  """
  import Plug.Conn
  alias Bilimbi.Base.Integration
  def init(opts), do: opts

  def call(conn, _) do
    if String.starts_with?(conn.request_path, "/api/v1/") or
         conn.request_path in [
           "/api/v1",
           "/oauth/device_authorization",
           "/oauth/token",
           "/.well-known/bilimbi",
           "/.well-known/oauth-authorization-server"
         ] do
      # The compatible audit trace column is varchar(12). Generate one trace
      # that fits it, rather than losing a suffix in audit and splitting the join.
      trace_id = :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)

      conn =
        conn |> assign(:api_trace_id, trace_id) |> put_resp_header("x-bilimbi-trace-id", trace_id)

      started = System.monotonic_time(:millisecond)
      Bilimbi.Base.Audit.Context.put(nil)

      register_before_send(conn, fn conn ->
        attrs = %{
          method: conn.method,
          endpoint: conn.request_path,
          operation: String.slice(conn.assigns[:agent_operation] || conn.request_path, 0, 255),
          response_status: conn.status,
          duration_ms: max(System.monotonic_time(:millisecond) - started, 0),
          connection_id: conn.assigns[:agent_connection_id],
          agent_id: label(conn, "x-bilimbi-agent-id"),
          run_id: label(conn, "x-bilimbi-run-id"),
          correlation_id: trace_id
        }

        {:ok, _} =
          if scope = conn.assigns[:agent_scope],
            do: Integration.record_incoming(scope, attrs),
            else: Integration.record_incoming_system(attrs)

        conn
      end)
    else
      conn
    end
  end

  defp label(conn, key) do
    case get_req_header(conn, key) do
      [value] -> if Bilimbi.Core.AgentAccess.valid_label?(value), do: value
      _ -> nil
    end
  end
end
