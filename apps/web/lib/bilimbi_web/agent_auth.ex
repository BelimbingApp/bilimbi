defmodule BilimbiWeb.AgentAuth do
  @moduledoc """
  Bearer authentication edge (ADR 0021). The token supplies claims, never grants.
  Re-prove the connection, live company, tenant and person before sealing a
  user actor with an agent facet. Cookies and caller-supplied identity are unused.
  """
  import Plug.Conn
  alias Bilimbi.Base.{Authz, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.{AgentAccess, Company, User}
  def init(opts), do: opts

  def call(conn, _) do
    with {:ok, token} <- bearer(conn),
         {:ok, claims} <- AgentAccess.authenticate(token),
         {:ok, tenant_id} <- Company.fetch_tenant_id_for_company(claims.company_id),
         true <- tenant_id == claims.tenant_id,
         {:ok, tenant} <- Tenancy.scope(tenant_id),
         {:ok, user} <- User.get_user(tenant, claims.company_id, claims.user_id) do
      scope =
        Authentication.sign_in(tenant, user.id, claims.company_id,
          agent: %{type: :agent, connection_id: claims.id, agent_id: stated_agent_id(conn)}
        )

      Bilimbi.Base.Audit.Context.put(%Bilimbi.Base.Audit.Context{
        actor_type: "user",
        actor_id: user.id,
        company_id: claims.company_id,
        tenant_id: tenant_id,
        trace_id: conn.assigns.api_trace_id,
        url: conn.request_path,
        ip_address: conn.remote_ip |> :inet.ntoa() |> to_string()
      })

      case AgentAccess.observe(scope) do
        :ok ->
          {:ok, actor} = Authz.scope_actor(scope)

          conn
          |> assign(:agent_scope, scope)
          |> assign(:agent_connection_id, claims.id)
          |> assign(:agent_actor, actor)

        _ ->
          refused(conn)
      end
    else
      _ -> refused(conn)
    end
  end

  # HTTP authentication scheme names are case-insensitive; token bytes are not.
  defp bearer(conn) do
    with [value] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(value, " ", trim: true),
         true <- String.downcase(scheme) == "bearer" do
      {:ok, token}
    else
      _ -> :error
    end
  end

  defp stated_agent_id(conn) do
    case get_req_header(conn, "x-bilimbi-agent-id") do
      [value] -> if AgentAccess.valid_label?(value), do: value
      _ -> nil
    end
  end

  defp refused(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "invalid_token"}))
    |> halt()
  end
end
