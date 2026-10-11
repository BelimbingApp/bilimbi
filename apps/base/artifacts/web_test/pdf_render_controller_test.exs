defmodule Bilimbi.Base.Artifacts.Web.RenderControllerTest do
  use BilimbiWeb.ConnCase, async: false
  import ExUnit.CaptureLog
  alias Bilimbi.Base.Artifacts.PDF.Tokens
  alias Bilimbi.Base.Artifacts.TestPDFOwner
  alias Bilimbi.Base.Tenancy.Scope

  setup %{conn: conn} do
    signed_in_identity!()
    authenticated = conn |> log_in_as() |> BilimbiWeb.UserAuth.fetch_current_scope([])
    %{scope: authenticated.assigns.current_scope.scope}
  end

  defp issue(scope, company \\ 73) do
    Tokens.issue(
      %{
        scope: scope,
        company: company,
        owner: TestPDFOwner,
        ref: %{subject: "report-1", kind: "report"},
        data: %{html: "<!doctype html><p>Private report</p>"}
      },
      60,
      100
    )
  end

  test "signed machine render needs no browser login and consumes exactly once", %{
    conn: conn,
    scope: scope
  } do
    {:ok, token} = issue(scope)
    response = get(conn, "/pdf/render/" <> token)
    assert response.status == 200
    assert response.resp_body == "<!doctype html><p>Private report</p>"
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert get_resp_header(response, "x-robots-tag") == ["noindex, nofollow"]
    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
    assert_received {:html_rendered, actor}
    assert actor == Scope.actor(scope)
    assert get(build_conn(), "/pdf/render/" <> token).status == 404
  end

  test "forged, revoked and unknown tokens never select a template", %{conn: conn, scope: scope} do
    {:ok, token} = issue(scope)
    assert get(conn, "/pdf/render/" <> token <> "x").status == 404
    Tokens.revoke(token)
    assert get(build_conn(), "/pdf/render/" <> token).status == 404
    assert get(build_conn(), "/pdf/render/unknown").status == 404
    refute_received {:html_rendered, _}
  end

  test "company scope mismatch and current permission refusal are consumed without HTML", %{
    conn: conn,
    scope: scope
  } do
    {:ok, token} = issue(scope, 51)
    assert get(conn, "/pdf/render/" <> token).status == 404
    {:ok, token} = issue(scope)
    Process.put({:deny, :create}, true)
    assert get(build_conn(), "/pdf/render/" <> token).status == 404
    assert get(build_conn(), "/pdf/render/" <> token).status == 404
    refute_received {:html_rendered, _}
  end

  test "deleted accounts invalidate already issued tokens", %{conn: conn, scope: scope} do
    {:ok, token} = issue(scope)
    {:ok, tenant_scope} = Bilimbi.Base.Tenancy.scope(41)
    assert :ok = Bilimbi.Core.User.delete_user(tenant_scope, 73, 91)
    assert get(conn, "/pdf/render/" <> token).status == 404
    refute_received {:html_rendered, _}
  end

  test "impersonation attribution reaches the template and ended impersonation is refused", %{
    conn: conn
  } do
    conn =
      conn
      |> log_in_as()
      |> impersonating_as(92, "Grace Hopper")
      |> BilimbiWeb.UserAuth.fetch_current_scope([])

    # This helper needs its borrowed account; fixtures stay behind Core APIs.
    case conn.assigns.current_scope do
      %{scope: scope} ->
        {:ok, token} = issue(scope)
        response = get(build_conn(), "/pdf/render/" <> token)
        assert response.status == 200
        assert_received {:html_rendered, actor}
        assert actor.impersonator_id == 92
        assert_received {:pdf_context, context}
        assert context.impersonator_id == 92
        assert context.actor_id == 91
        {:ok, next} = issue(scope)

        assert {:ok, :terminated} =
                 Bilimbi.Base.Session.terminate_session(
                   actor.impersonation_session_id,
                   "different-current-session"
                 )

        assert get(build_conn(), "/pdf/render/" <> next).status == 404

      _ ->
        flunk("impersonation scope was not proven")
    end
  end

  test "bearer paths and template exception contents never enter request logs", %{
    conn: conn,
    scope: scope
  } do
    previous_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    {:ok, token} = issue(scope)

    log =
      capture_log(fn ->
        assert get(conn, "/pdf/render/" <> token).status == 200
        assert get(build_conn(), "/pdf/render/" <> token).status == 404
        get(build_conn(), "/")
      end)

    assert log =~ "GET /"
    refute log =~ token

    {:ok, failed} = issue(scope)
    Process.put(:raise_pdf_html, true)

    log =
      capture_log(fn ->
        response = get(build_conn(), "/pdf/render/" <> failed)
        assert response.status == 500
        assert response.resp_body == ""
      end)

    refute log =~ failed
    refute log =~ "Private report"
    assert get(build_conn(), "/pdf/render/" <> failed).status == 404
  end

  test "render context carries the signed actor and a token-free audit URL", %{
    conn: conn,
    scope: scope
  } do
    {:ok, token} = issue(scope)
    assert get(conn, "/pdf/render/" <> token).status == 200
    assert_received {:pdf_context, context}
    assert context.actor_type == "user"
    assert context.actor_id == 91
    assert context.company_id == 73
    assert context.tenant_id == 41
    assert context.url == "/pdf/render/:token"
    refute context.url =~ token
  end

  test "render callbacks receive the current tenant identity with the original sealed actor", %{
    conn: conn,
    scope: scope
  } do
    stale = %Scope{scope | tenant: %{scope.tenant | is_platform_operator: false}}
    refute Scope.platform_operator?(stale)
    {:ok, token} = issue(stale)
    assert get(conn, "/pdf/render/" <> token).status == 200
    assert_received {:pdf_platform_operator, true}
    assert_received {:html_rendered, actor}
    assert actor == Scope.actor(scope)
  end
end
