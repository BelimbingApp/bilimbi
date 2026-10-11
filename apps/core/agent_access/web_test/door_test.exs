defmodule Bilimbi.Core.AgentAccess.DoorTest do
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Tenancy.{Authentication, Scope}
  alias Bilimbi.Core.AgentAccess
  alias Bilimbi.Core.AgentAccess.{Connection, Device, Token}
  import Ecto.Query

  setup do
    signed_in_identity!()
    AgentAccess.TestFixtures.create_tables!()
    Bilimbi.Base.Integration.TestFixtures.create_exchanges_table!()
    grant_capabilities!(~w(admin.company.list admin.company.view))
    {:ok, tenant} = Tenancy.scope(41)
    %{scope: Authentication.sign_in(tenant, 91, 73)}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp start do
    {:ok, device} = AgentAccess.start_device(AgentAccess.client_id(), "codex/model-high")
    device
  end

  defp approved(scope) do
    device = start()

    :ok =
      AgentAccess.decide(
        scope,
        device.user_code,
        :approve,
        DateTime.add(now(), 86400)
      )

    {:ok, tokens} = AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
    tokens
  end

  defp bearer(conn, tokens, agent \\ "codex/model-high") do
    conn
    |> put_req_header("authorization", "Bearer " <> tokens.access_token)
    |> put_req_header("x-bilimbi-agent-id", agent)
    |> put_req_header("x-bilimbi-run-id", "run-1")
  end

  test "discovery advertises this server and the public device client", %{conn: conn} do
    metadata = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)
    assert metadata["grant_types_supported"] == [AgentAccess.device_grant(), "refresh_token"]
    assert metadata["token_endpoint_auth_methods_supported"] == ["none"]
    descriptor = conn |> recycle() |> get("/.well-known/bilimbi") |> json_response(200)
    assert descriptor["api_version"] == "1"
    assert descriptor["client_id"] == AgentAccess.client_id()
  end

  test "device endpoints return polling errors and hashed single-use credentials", %{
    conn: conn,
    scope: scope
  } do
    assert {:error, :invalid_request} = AgentAccess.start_device(AgentAccess.client_id(), " ")

    response =
      conn
      |> post("/oauth/device_authorization", %{
        client_id: AgentAccess.client_id(),
        agent_id: "codex/model-high"
      })
      |> json_response(200)

    device = Repo.one!(Device)
    refute device.device_hash == response["device_code"]
    refute device.user_hash == response["user_code"]

    assert {:error, :authorization_pending} =
             AgentAccess.exchange(AgentAccess.client_id(), response["device_code"])

    assert {:error, :slow_down} =
             AgentAccess.exchange(AgentAccess.client_id(), response["device_code"])

    :ok =
      AgentAccess.decide(
        scope,
        response["user_code"],
        :approve,
        DateTime.add(now(), 86400)
      )

    # Advance the protocol clock deterministically, rather than sleeping.
    Repo.update_all(Device, set: [next_poll_at: DateTime.add(now(), -1)])

    tokens =
      conn
      |> recycle()
      |> post("/oauth/token", %{
        client_id: AgentAccess.client_id(),
        device_code: response["device_code"],
        grant_type: AgentAccess.device_grant()
      })
      |> json_response(200)

    assert tokens["expires_in"] in 3599..3600

    refute Enum.any?(
             Repo.all(Token),
             &(&1.token_hash in [tokens["access_token"], tokens["refresh_token"]])
           )

    assert {:error, :invalid_grant} =
             AgentAccess.exchange(AgentAccess.client_id(), response["device_code"])
  end

  test "search, describe, guide and call act as the named person and log the run", %{
    conn: conn,
    scope: scope
  } do
    tokens = approved(scope)

    conn =
      bearer(conn, tokens) |> put_req_header("authorization", "bearer " <> tokens.access_token)

    assert %{"result" => [%{"key" => "core.company.list"} | _]} =
             conn |> get("/api/v1/search?q=find%20companies") |> json_response(200)

    assert %{"key" => "core.company.list"} =
             conn
             |> recycle()
             |> bearer(tokens)
             |> get("/api/v1/operations/core.company.list")
             |> json_response(200)

    assert %{"body" => _} =
             conn
             |> recycle()
             |> bearer(tokens)
             |> get("/api/v1/guides/core.company")
             |> json_response(200)

    assert %{"result" => [_ | _]} =
             conn
             |> recycle()
             |> bearer(tokens, "codex/new-high")
             |> post("/api/v1/operations/core.company.list/call", %{input: %{}})
             |> json_response(200)

    row =
      Repo.one!(
        from e in Bilimbi.Base.Integration.Exchange, where: e.operation == "core.company.list"
      )

    assert row.person_id == 91
    assert row.run_id == "run-1"
    assert row.agent_id == "codex/new-high"
    assert row.connection_id == to_string(Repo.one!(Connection).id)
    assert row.request_body == nil
    assert row.response_body == nil
    assert is_binary(row.correlation_id)
    {:ok, [connection]} = AgentAccess.list_connections(scope)
    assert Map.has_key?(connection.seen_agent_ids, "codex/new-high")

    {:ok, mutations} =
      Bilimbi.Base.Audit.list_subject_mutations(
        scope,
        "Bilimbi.Core.AgentAccess.Connection",
        connection.id
      )

    mutation = Enum.find(mutations, &(&1.event == "updated"))
    assert mutation.actor_type == "user"
    assert mutation.actor_id == 91
    assert mutation.trace_id == row.correlation_id
  end

  test "missing tokens and metadata fail without cookies supplying authority and still log", %{
    conn: conn,
    scope: scope
  } do
    assert conn |> log_in_as() |> get("/api/v1/search?q=company") |> json_response(401) == %{
             "error" => "invalid_token"
           }

    tokens = approved(scope)

    assert conn
           |> recycle()
           |> put_req_header("authorization", "Bearer " <> tokens.access_token)
           |> get("/api/v1/search?q=company")
           |> json_response(401) == %{"error" => "invalid_token"}

    assert Repo.aggregate(Bilimbi.Base.Integration.Exchange, :count) == 2
  end

  test "refresh rotates and replay revokes all tokens", %{scope: scope} do
    tokens = approved(scope)
    {:ok, next} = AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)
    assert next.refresh_token != tokens.refresh_token
    assert {:ok, _} = AgentAccess.authenticate(next.access_token)

    assert {:error, :invalid_grant} =
             AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)

    assert {:error, :invalid_token} = AgentAccess.authenticate(next.access_token)
    assert {:error, :invalid_token} = AgentAccess.authenticate(tokens.access_token)
  end

  test "expired, denied and wrong-client device grants are refused", %{scope: scope} do
    device = start()
    assert {:error, :invalid_client} = AgentAccess.exchange("other", device.device_code)
    :ok = AgentAccess.decide(scope, device.user_code, :deny, DateTime.add(now(), 60))

    assert {:error, :access_denied} =
             AgentAccess.exchange(AgentAccess.client_id(), device.device_code)

    device = start()

    Repo.update_all(from(d in Device, where: d.status == "pending"),
      set: [expires_at: DateTime.add(now(), -1)]
    )

    assert {:error, :expired_token} =
             AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
  end

  test "revocation and expired access end bearer access", %{scope: scope} do
    tokens = approved(scope)
    {:ok, [connection]} = AgentAccess.list_connections(scope)
    :ok = AgentAccess.revoke(scope, connection.id)
    assert {:error, :invalid_token} = AgentAccess.authenticate(tokens.access_token)
    tokens = approved(scope)

    Repo.update_all(from(t in Token, where: t.kind == "access"),
      set: [expires_at: DateTime.add(now(), -1)]
    )

    assert {:error, :invalid_token} = AgentAccess.authenticate(tokens.access_token)
  end

  test "an account moved to another company cannot use or refresh its old connection", %{
    conn: conn,
    scope: scope
  } do
    tokens = approved(scope)
    grant_capabilities!("admin.user.update")

    Bilimbi.Core.Company.TestFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      code: "new_company"
    })

    assert {:ok, _} = Bilimbi.Core.User.reassign_user_company(scope, 73, 91, 74)

    assert conn |> bearer(tokens) |> get("/api/v1/search?q=company") |> json_response(401) == %{
             "error" => "invalid_token"
           }

    assert {:error, :invalid_grant} =
             AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)
  end

  test "deleted people lose their grants and credentials", %{scope: scope} do
    tokens = approved(scope)
    grant_capabilities!("admin.user.delete")
    assert :ok = Bilimbi.Core.User.delete_user(scope, 73, 91)
    assert Repo.aggregate(Connection, :count) == 0
    assert Repo.aggregate(Token, :count) == 0
    assert {:error, :invalid_token} = AgentAccess.authenticate(tokens.access_token)

    assert {:error, :invalid_grant} =
             AgentAccess.refresh(AgentAccess.client_id(), tokens.refresh_token)
  end

  test "agent facets are sealed, cannot delegate or manage connections", %{scope: scope} do
    actor = Scope.actor(scope)
    {:ok, tenant} = Tenancy.scope(41)

    facet_scope =
      Authentication.sign_in(tenant, actor.user_id, actor.company_id,
        agent: %{type: :agent, connection_id: 1, agent_id: "codex/model-high"}
      )

    assert Scope.actor(facet_scope).type == :user
    assert {:error, :agent_delegation_not_enabled} = Authentication.delegate(facet_scope)
    assert {:error, :person_required} = AgentAccess.list_connections(facet_scope)
    forged = %{facet_scope | actor: %{Scope.actor(facet_scope) | facet: nil}}
    assert_raise Bilimbi.Base.Tenancy.ForgedActorError, fn -> Scope.actor(forged) end
  end

  test "machine endpoints refuse multipart files and measure the refusal", %{
    conn: conn,
    scope: scope
  } do
    tokens = approved(scope)

    body =
      "--boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"reference.png\"\r\nContent-Type: image/png\r\n\r\nimage\r\n--boundary--\r\n"

    assert_error_sent 415, fn ->
      conn
      |> bearer(tokens)
      |> put_req_header("content-type", "multipart/form-data; boundary=boundary")
      |> post("/api/v1/operations/core.company.list/call", body)
    end

    row = Repo.one!(Bilimbi.Base.Integration.Exchange)
    assert row.response_status == 415
    assert row.request_body == nil
  end

  test "malformed JSON is refused and measured without retaining its bytes", %{
    conn: conn,
    scope: scope
  } do
    tokens = approved(scope)

    assert_error_sent 400, fn ->
      conn
      |> bearer(tokens)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/operations/core.company.list/call", "{")
    end

    row = Repo.one!(Bilimbi.Base.Integration.Exchange)
    assert row.response_status == 400
    assert row.request_body == nil
  end

  test "live grants and tenant boundaries are enforced through HTTP", %{conn: conn, scope: scope} do
    tokens = approved(scope)
    Bilimbi.Core.Company.TestFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    Bilimbi.Core.Company.TestFixtures.insert_company!(%{id: 74, tenant_id: 42, code: "other"})

    assert conn
           |> bearer(tokens)
           |> post("/api/v1/operations/core.company.get/call", %{input: %{company_id: 74}})
           |> json_response(404) == %{"error" => "not_found"}

    {:ok, :stored} =
      Bilimbi.Base.Authz.put_principal_capability(
        scope,
        73,
        :user,
        91,
        "admin.company.list",
        false
      )

    assert conn
           |> recycle()
           |> bearer(tokens)
           |> post("/api/v1/operations/core.company.list/call", %{input: %{}})
           |> json_response(403) == %{"error" => "forbidden", "reason" => "missing_capability"}

    assert conn
           |> recycle()
           |> bearer(tokens)
           |> post("/api/v1/operations/core.company.get/call", %{input: %{}})
           |> json_response(422) == %{
             "error" => "invalid_input",
             "fields" => %{"company_id" => ["is required"]}
           }
  end

  test "field restrictions survive the bearer edge", %{conn: conn, scope: scope} do
    tokens = approved(scope)
    grant_capabilities!("admin.authz.field.manage")

    {:ok, role} =
      Bilimbi.Base.Authz.create_role(scope, 73, %{
        name: "Restricted reader",
        code: "restricted_reader"
      })

    {:ok, _} =
      Bilimbi.Base.Authz.put_field_restriction(scope, "companies", "jurisdiction", [role.id])

    {:ok, :assigned} = Bilimbi.Base.Authz.assign_role(scope, 73, :user, 91, role.id)

    assert %{"result" => %{"jurisdiction" => %{"restricted" => true}}} =
             conn
             |> bearer(tokens)
             |> post("/api/v1/operations/core.company.get/call", %{input: %{company_id: 73}})
             |> json_response(200)
  end

  test "a connection belongs to its person and impersonation cannot consent", %{scope: scope} do
    _tokens = approved(scope)
    {:ok, [connection]} = AgentAccess.list_connections(scope)
    {:ok, tenant} = Tenancy.scope(41)
    other = Authentication.sign_in(tenant, 92, 73)
    assert {:ok, []} = AgentAccess.list_connections(other)
    assert {:error, :not_found} = AgentAccess.revoke(other, connection.id)

    borrowed =
      Authentication.sign_in(tenant, 91, 73,
        impersonator_id: 92,
        impersonation_session_id: "borrowed"
      )

    assert {:error, :person_required} = AgentAccess.list_connections(borrowed)
    device = start()

    assert {:error, :person_required} =
             AgentAccess.decide(borrowed, device.user_code, :approve, DateTime.add(now(), 86400))
  end

  test "facets lose platform, access-control and write capabilities even under direct grants" do
    grant_capabilities!(
      ~w(admin.system.database-table.list admin.authz.role.list admin.company.update)
    )

    {:ok, tenant} = Tenancy.scope(41)

    facet =
      Authentication.sign_in(tenant, 91, 73,
        agent: %{type: :agent, connection_id: 1, agent_id: "codex/model-high"}
      )

    assert Bilimbi.Base.Authz.can(facet, "admin.system.database-table.list").reason ==
             :denied_agent_platform

    assert Bilimbi.Base.Authz.can(facet, "admin.authz.role.list").reason ==
             :denied_agent_access_control

    assert Bilimbi.Base.Authz.can(facet, "admin.company.update").reason ==
             :denied_agent_writes_off

    {:ok, actor} = Bilimbi.Base.Authz.scope_actor(facet)
    allowed = Bilimbi.Base.Authz.effective_capabilities(actor).allowed
    refute "admin.system.database-table.list" in allowed
    refute "admin.authz.role.list" in allowed
    refute "admin.company.update" in allowed
    assert "admin.company.list" in allowed
  end

  test "registered writes still answer writes_not_enabled through HTTP", %{
    conn: conn,
    scope: scope
  } do
    tokens = approved(scope)
    grant_capabilities!("admin.company.update")
    alias Bilimbi.Base.AgentApi.{ContributionValidator, TestFixtures, TestOperations}
    alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
    entry = Enum.find(TestOperations.payload().operations, &(&1.kind == :write))
    entry = %{entry | capability: "admin.company.update"}

    registry =
      ContributionValidator.validate_contributions!([
        %{descriptor: TestFixtures.descriptor(), payload: %{operations: [entry]}}
      ])

    original = ContributionRegistry.snapshot!()

    ContributionRegistry.put_consumers_for_test!(
      Map.put(original.consumers, :agent_api, registry),
      "door-write"
    )

    on_exit(fn ->
      ContributionRegistry.put_consumers_for_test!(original.consumers, original.graph_fingerprint)
    end)

    assert conn
           |> bearer(tokens)
           |> post("/api/v1/operations/base.agent_api.record.update/call", %{
             input: %{record_id: 5, label: "New"}
           })
           |> json_response(409) == %{"error" => "writes_not_enabled"}
  end

  test "impersonation withholds consent and explains why connections cannot be read", %{
    conn: conn
  } do
    device = start()
    conn = conn |> log_in_as() |> impersonating_as(92, "Operator")
    {:ok, view, _} = live(conn, "/settings/agent-connections")
    assert has_element?(view, "#connections-error")
    refute has_element?(view, "#connections-empty")
    {:ok, view, _} = live(conn, "/oauth/device")
    view |> form("#device-code-form", device: %{user_code: device.user_code}) |> render_submit()
    assert has_element?(view, "#device-error")
    refute has_element?(view, "#device-consent")
  end

  test "device consent requires an explicit action and connections can be revoked", %{conn: conn} do
    device = start()
    conn = log_in_as(conn)
    {:ok, view, _} = live(conn, "/oauth/device?user_code=" <> device.user_code)
    assert has_element?(view, "#device-code-form")
    refute has_element?(view, "#device-consent")
    view |> form("#device-code-form", device: %{user_code: device.user_code}) |> render_submit()
    assert has_element?(view, "#device-consent")

    view
    |> form("#device-approval-form",
      grant: %{end_date: Date.utc_today() |> Date.add(2) |> Date.to_iso8601()}
    )
    |> render_submit()

    refute has_element?(view, "#device-consent")
    {:ok, view, _} = live(conn, "/settings/agent-connections")
    connection = Repo.one!(Connection)
    assert has_element?(view, "#revoke-#{connection.id}")
    view |> element("#revoke-#{connection.id}") |> render_click()
    view |> element("#revoke-connection-dialog-confirm") |> render_click()
    assert Repo.get!(Connection, connection.id).revoked_at
  end
end
