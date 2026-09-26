defmodule BilimbiWeb.ScopeActorTest do
  @moduledoc """
  A signed-in request's scope names who is signed in. Every module call made
  with `@current_scope.scope` — from a controller or a LiveView, on the
  disconnected render and the connected mount alike — carries the actor the
  authentication edge sealed, and an anonymous request carries none.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @operator_id 91
  @target_id 92

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    for {id, name} <- [{@operator_id, "Operator"}, {@target_id, "Target"}] do
      UserFixtures.insert_user!(%{
        id: id,
        company_id: 73,
        name: name,
        email: "user#{id}@example.com",
        password_hash: "not-used"
      })
    end

    grant_capabilities!(["admin.user.impersonate"], user_id: @operator_id)
    :ok
  end

  test "an HTTP request's scope carries the signed-in user", %{conn: conn} do
    conn = conn |> log_in_as() |> get(~p"/dashboard")

    assert html_response(conn, 200)
    scope = conn.assigns.current_scope.scope

    assert %Actor{type: :user, user_id: @operator_id, company_id: 73, impersonator_id: nil} =
             Scope.actor(scope)

    assert Scope.tenant_id(scope) == 41
    assert Authz.can(scope, "admin.user.impersonate").allowed
  end

  test "a connected LiveView's scope carries the signed-in user", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    scope = live_scope(view)

    assert %Actor{type: :user, user_id: @operator_id, company_id: 73, impersonator_id: nil} =
             Scope.actor(scope)

    assert Authz.can(scope, "admin.user.impersonate").allowed
  end

  test "under impersonation the actor is the account acted as, and names the operator", %{
    conn: conn
  } do
    impersonating =
      conn
      |> log_in_as(%{"user_id" => @operator_id, "company_id" => 73})
      |> post(~p"/admin/impersonate/#{@target_id}")

    {:ok, view, _html} = live(impersonating, ~p"/dashboard")

    assert %Actor{type: :user, user_id: @target_id, impersonator_id: @operator_id} =
             view |> live_scope() |> Scope.actor()

    # The borrowed session is judged on the target's grants, not the operator's.
    refute view |> live_scope() |> Authz.can("admin.user.impersonate") |> Map.fetch!(:allowed)
  end

  test "an anonymous request has no scope to carry an actor", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200)
    assert conn.assigns.current_scope == nil
  end

  # The LiveView process's own assigns: the scope its event handlers pass to
  # module APIs, resolved by the connected mount rather than the HTTP request.
  defp live_scope(view) do
    %{socket: %{assigns: %{current_scope: %{scope: %Scope{} = scope}}}} = :sys.get_state(view.pid)
    scope
  end
end
