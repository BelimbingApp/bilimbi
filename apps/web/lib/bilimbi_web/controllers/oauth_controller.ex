defmodule BilimbiWeb.OAuthController do
  use BilimbiWeb, :controller
  alias Bilimbi.Core.AgentAccess

  def metadata(conn, _) do
    base = BilimbiWeb.Endpoint.url()

    json(conn, %{
      issuer: base,
      device_authorization_endpoint: url(~p"/oauth/device_authorization"),
      token_endpoint: url(~p"/oauth/token"),
      response_types_supported: [],
      grant_types_supported: [AgentAccess.device_grant(), "refresh_token"],
      token_endpoint_auth_methods_supported: ["none"]
    })
  end

  def descriptor(conn, _) do
    json(conn, %{
      api_base: BilimbiWeb.Endpoint.url() <> "/api/v1",
      api_version: "1",
      plan_endpoint: url(~p"/api/v1/plans"),
      commit_endpoint: url(~p"/api/v1/plans/commit"),
      server_name: URI.parse(BilimbiWeb.Endpoint.url()).host,
      client_id: AgentAccess.client_id()
    })
  end

  def device(conn, params) do
    case throttle(conn, :device) do
      :allow ->
        case AgentAccess.start_device(params["client_id"], params["agent_id"]) do
          {:ok, result} ->
            uri = url(~p"/oauth/device")

            reply(
              conn,
              {:ok,
               Map.merge(result, %{
                 verification_uri: uri,
                 verification_uri_complete:
                   url(~p"/oauth/device?#{[user_code: result.user_code]}")
               })}
            )

          error ->
            reply(conn, error)
        end

      _ ->
        reply(conn, {:error, :slow_down})
    end
  end

  def token(conn, params) do
    result =
      case throttle(conn, :token) do
        :allow ->
          cond do
            is_nil(params["grant_type"]) ->
              {:error, :invalid_request}

            params["grant_type"] == AgentAccess.device_grant() ->
              AgentAccess.exchange(params["client_id"], params["device_code"])

            params["grant_type"] == "refresh_token" ->
              AgentAccess.refresh(params["client_id"], params["refresh_token"])

            true ->
              {:error, :unsupported_grant_type}
          end

        _ ->
          {:error, :slow_down}
      end

    reply(conn, result)
  end

  defp throttle(conn, kind) do
    key = {:oauth, kind, conn.remote_ip}

    result =
      BilimbiWeb.RateLimit.attempt_allowed?(
        key,
        Bilimbi.Base.Settings.get("agent_access.oauth_requests_per_minute")
      )

    if result == :allow, do: BilimbiWeb.RateLimit.record_attempt(key)
    result
  end

  defp reply(conn, result) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

    case result do
      {:ok, body} -> json(conn, body)
      {:error, reason} -> conn |> put_status(400) |> json(%{error: reason})
    end
  end
end
