defmodule Bilimbi.Core.AgentAccess.Web.McpOAuthTest do
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{Repo, Settings, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.AgentAccess
  alias Bilimbi.Core.AgentAccess.AuthorizationCode

  @redirect_uri "https://chatgpt.com/connector_platform_oauth_redirect"
  @verifier String.duplicate("a", 43)
  setup do
    signed_in_identity!()
    AgentAccess.TestFixtures.create_tables!()
    Bilimbi.Base.Integration.TestFixtures.create_exchanges_table!()

    {:ok, _} =
      Settings.put("agent_access.oauth_clients", %{
        "bilimbi-chatgpt" => %{"name" => "ChatGPT", "redirect_uris" => [@redirect_uri]}
      })

    {:ok, tenant} = Tenancy.scope(41)
    %{scope: Authentication.sign_in(tenant, 91, 73)}
  end

  defp request do
    %{
      "response_type" => "code",
      "client_id" => "bilimbi-chatgpt",
      "redirect_uri" => @redirect_uri,
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256",
      "resource" => BilimbiWeb.MCPController.resource(),
      "scope" => "bilimbi",
      "state" => "state-123"
    }
  end

  defp redeem(conn, code, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "grant_type" => "authorization_code",
          "client_id" => "bilimbi-chatgpt",
          "redirect_uri" => @redirect_uri,
          "code" => code,
          "code_verifier" => @verifier,
          "resource" => BilimbiWeb.MCPController.resource()
        },
        overrides
      )

    conn |> recycle() |> post("/oauth/token", params)
  end

  test "metadata advertises PKCE and resource discovery", %{conn: conn} do
    metadata = get(conn, "/.well-known/oauth-authorization-server") |> json_response(200)
    assert metadata["authorization_endpoint"] == BilimbiWeb.Endpoint.url() <> "/oauth/authorize"
    assert "authorization_code" in metadata["grant_types_supported"]
    assert metadata["code_challenge_methods_supported"] == ["S256"]

    resource =
      get(recycle(conn), "/.well-known/oauth-protected-resource/mcp") |> json_response(200)

    assert resource["resource"] == BilimbiWeb.MCPController.resource()
    assert resource["scopes_supported"] == ["bilimbi"]
  end

  test "opening consent never issues a grant; approval returns code, state and issuer", %{
    conn: conn
  } do
    {:ok, view, _} = live(log_in_as(conn), "/oauth/authorize?" <> URI.encode_query(request()))
    assert has_element?(view, "#oauth-consent")
    assert Repo.aggregate(AuthorizationCode, :count) == 0

    view
    |> form("#oauth-consent-form",
      grant: %{end_date: Date.utc_today() |> Date.add(1) |> Date.to_iso8601()}
    )
    |> render_submit()

    {redirect, _flash} = assert_redirect(view)
    uri = URI.parse(redirect)
    assert uri.host == "chatgpt.com"
    query = URI.decode_query(uri.query)
    assert query["state"] == "state-123"
    assert query["iss"] == BilimbiWeb.Endpoint.url()
    assert is_binary(query["code"])
    refute Repo.one!(AuthorizationCode).code_hash == query["code"]
    assert redeem(conn, query["code"]) |> json_response(200) |> Map.fetch!("scope") == "bilimbi"
  end

  test "a signed-out connection resumes the complete OAuth request after sign-in", %{conn: conn} do
    target = "/oauth/authorize?" <> URI.encode_query(request())
    anonymous = get(conn, target)
    assert redirected_to(anonymous) == "/"
    assert get_session(anonymous, "user_return_to") == target
    assert Repo.aggregate(AuthorizationCode, :count) == 0

    signed_in =
      anonymous
      |> recycle()
      |> post("/session", %{
        "login" => %{"_token" => BilimbiWeb.UserAuth.sign_login_token(session_user())}
      })

    assert redirected_to(signed_in) == target
    {:ok, view, _} = live(recycle(signed_in), target)
    assert has_element?(view, "#oauth-consent-approve")
    assert Repo.aggregate(AuthorizationCode, :count) == 0
  end

  test "invalid callbacks and impersonation cannot approve", %{conn: conn, scope: scope} do
    invalid = Map.put(request(), "redirect_uri", "https://attacker.test/callback")

    assert {:error, :invalid_redirect_uri} =
             AgentAccess.authorization_request(invalid, BilimbiWeb.MCPController.resource())

    {:ok, view, _} = live(log_in_as(conn), "/oauth/authorize?" <> URI.encode_query(invalid))
    assert has_element?(view, "#oauth-consent-error")
    refute has_element?(view, "#oauth-consent-approve")

    borrowed = conn |> recycle() |> log_in_as() |> impersonating_as(92, "Operator")
    {:ok, borrowed_view, _} = live(borrowed, "/oauth/authorize?" <> URI.encode_query(request()))
    assert has_element?(borrowed_view, "#oauth-consent-error")
    refute has_element?(borrowed_view, "#oauth-consent-approve")
    {:ok, user_scope} = Tenancy.scope(41)

    impersonated =
      Authentication.sign_in(user_scope, 91, 73,
        impersonator_id: 92,
        impersonation_session_id: "borrowed"
      )

    assert {:error, :person_required} =
             AgentAccess.authorize(
               impersonated,
               request(),
               BilimbiWeb.MCPController.resource(),
               DateTime.add(DateTime.utc_now(), 600)
             )

    agent =
      Authentication.sign_in(user_scope, 91, 73,
        agent: %{type: :agent, connection_id: 1, agent_id: "test"}
      )

    assert {:error, :person_required} =
             AgentAccess.authorize(
               agent,
               request(),
               BilimbiWeb.MCPController.resource(),
               DateTime.add(DateTime.utc_now(), 600)
             )

    assert {:ok, _} =
             AgentAccess.authorize(
               scope,
               request(),
               BilimbiWeb.MCPController.resource(),
               DateTime.add(DateTime.utc_now(), 600)
             )
  end

  test "PKCE, client, callback and resource are bound and code replay revokes issued tokens", %{
    conn: conn,
    scope: scope
  } do
    resource = BilimbiWeb.MCPController.resource()

    {:ok, code} =
      AgentAccess.authorize(scope, request(), resource, DateTime.add(DateTime.utc_now(), 3600))

    for invalid <- [
          %{"code_verifier" => String.duplicate("b", 43)},
          %{"client_id" => "other"},
          %{"redirect_uri" => "https://attacker.test/callback"},
          %{"resource" => "https://other.test/mcp"}
        ] do
      assert redeem(conn, code, invalid) |> json_response(400) == %{"error" => "invalid_grant"}
    end

    tokens = redeem(conn, code) |> json_response(200)
    assert {:ok, _} = AgentAccess.authenticate(tokens["access_token"], resource)
    assert {:error, :invalid_token} = AgentAccess.authenticate(tokens["access_token"])

    assert {:error, :invalid_grant} =
             AgentAccess.refresh(AgentAccess.client_id(), tokens["refresh_token"])

    assert {:ok, rotated} =
             AgentAccess.refresh("bilimbi-chatgpt", tokens["refresh_token"], resource)

    assert {:ok, _} = AgentAccess.authenticate(rotated.access_token, resource)
    assert redeem(conn, code) |> json_response(400) == %{"error" => "invalid_grant"}
    assert {:error, :invalid_token} = AgentAccess.authenticate(rotated.access_token, resource)
  end

  test "plain PKCE, unknown scopes, targets and clients fail before consent" do
    for {key, value} <- [
          {"code_challenge_method", "plain"},
          {"scope", "admin"},
          {"resource", "https://other.test/mcp"},
          {"client_id", "unregistered"}
        ] do
      assert {:error, _} =
               AgentAccess.authorization_request(
                 Map.put(request(), key, value),
                 BilimbiWeb.MCPController.resource()
               )
    end
  end
end
