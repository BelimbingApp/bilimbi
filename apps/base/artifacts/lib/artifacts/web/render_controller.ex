defmodule Bilimbi.Base.Artifacts.Web.RenderController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]
  alias Bilimbi.Base.Artifacts
  alias Bilimbi.Base.Artifacts.PDF.Tokens
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope

  def show(conn, %{"token" => token}) do
    case Tokens.consume(token) do
      {:ok, claims} -> render_claims(conn, claims)
      _ -> conn |> private_headers() |> send_resp(404, "")
    end
  rescue
    # Template exceptions can contain private data. Return a fixed failure
    # without handing the exception or its contents to Phoenix's error logger.
    _ -> conn |> private_headers() |> send_resp(500, "")
  end

  defp render_claims(conn, %{
         scope: %Scope{} = scope,
         company: company,
         owner: owner,
         ref: ref,
         data: data
       }) do
    %Context{} = previous = Context.get()
    route = Phoenix.Router.route_info(router_module(conn), conn.method, conn.path_info, conn.host)

    # The signed scope, rather than an unrelated browser login, attributes any
    # authorization decisions or owner writes. Store the route pattern so the
    # bearer token cannot enter a captured mutation's URL; restore on all exits.
    Context.put(%{Context.from_scope(scope) | company_id: company, url: route.route})

    try do
      with {:ok, live_scope} <- Tenancy.scope(Scope.tenant_id(scope)),
           scope = %Scope{scope | tenant: live_scope.tenant},
           :ok <- verify_actor(scope),
           :ok <- Artifacts.authorize(scope, company, owner, :create, ref),
           {:ok, body} when is_binary(body) <- owner.render_html(scope, company, ref, data) do
        conn
        |> private_headers()
        |> put_resp_header(
          "content-security-policy",
          "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        )
        |> html(body)
      else
        _ -> conn |> private_headers() |> send_resp(404, "")
      end
    after
      Context.put(previous)
    end
  end

  defp verify_actor(scope) do
    case Scope.actor(scope) do
      %{type: :user} ->
        case ContributionRegistry.consumer!(:actor_verifier) do
          nil -> {:error, :no_actor_verifier}
          verifier -> verifier.verify_actor(scope)
        end

      %{type: :system} ->
        :ok
    end
  end

  defp private_headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
