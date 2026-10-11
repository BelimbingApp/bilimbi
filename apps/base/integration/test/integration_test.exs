defmodule Bilimbi.Base.IntegrationTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.{Audit, Authz, Integration, Repo, Settings}
  alias Bilimbi.Base.Integration.{Contributions, Exchange, Redaction, TestFixtures}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  @list "admin.system.outbound-exchange.list"
  @payload "admin.system.outbound-exchange.payload.view"
  @delete "admin.system.outbound-exchange.delete"

  setup do
    TestFixtures.create_exchanges_table!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    Bilimbi.Base.Settings.TestFixtures.create_settings_table!()

    descriptor = %{
      id: "base/integration",
      otp_app: :bilimbi_base_integration,
      namespace: Bilimbi.Base.Integration
    }

    contributions = Contributions.contributions()

    authz =
      Bilimbi.Base.Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{
            id: "base/authz",
            otp_app: :bilimbi_base_authz,
            namespace: Bilimbi.Base.Authz
          },
          payload: %{
            domains: %{"admin" => "Administration"},
            verbs: ~w(list view delete),
            roles: %{"auditor" => %{name: "Auditor"}, "system_viewer" => %{name: "System Viewer"}},
            company_directory: Bilimbi.Base.Authz.TestCompanyDirectory
          }
        },
        %{descriptor: descriptor, payload: contributions.authz}
      ])

    settings =
      Bilimbi.Base.Settings.ContributionValidator.validate_contributions!([
        %{descriptor: descriptor, payload: contributions.settings}
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz, settings: settings})
    on_exit(&ContributionRegistry.clear_for_test!/0)
    system = TenancyFixtures.scope(1)
    scope = Authentication.sign_in(system, 7, 10)
    %{scope: scope, system: system}
  end

  defp grant(system, capability) do
    {:ok, :stored} = Authz.put_principal_capability(system, 10, :user, 7, capability, true)
  end

  test "gateway preserves response and records only safe metadata by default", %{
    scope: scope,
    system: system
  } do
    grant(system, @list)
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{token: "response-secret"}) end)

    assert {:ok, %{status: 200}} =
             Integration.request(
               scope,
               %{system: "example", operation: "lookup", owner_type: "core/example", owner_id: 8},
               url: "https://example.test/items?api_key=query-secret",
               method: :post,
               json: %{password: "request-secret"},
               headers: [{"authorization", "Bearer header-secret"}],
               plug: {Req.Test, __MODULE__}
             )

    assert {:ok, %{entries: [entry]}} = Integration.list_page(scope)
    assert entry.method == "POST"
    assert entry.host == "example.test"
    assert entry.path == "/items"
    assert entry.endpoint == "https://example.test/items"
    assert entry.person_id == 7
    assert entry.owner_id == 8
    assert entry.duration_ms >= 0
    refute Map.has_key?(entry, :request_body)
    row = Repo.get!(Exchange, entry.id)
    assert is_nil(row.request_body) and is_nil(row.response_body) and is_nil(row.request_headers)

    assert {:ok, []} =
             Audit.list_subject_mutations(scope, Exchange.__audit_auditable_type__(), entry.id)
  end

  test "HTTP and connection failures are logged with no blanket retry", %{
    scope: scope,
    system: system
  } do
    grant(system, @list)

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.text("unavailable")
    end)

    assert {:ok, %{status: 503}} =
             Integration.request(scope, %{operation: "http.fail"},
               url: "https://example.test/fail",
               plug: {Req.Test, __MODULE__}
             )

    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, %Req.TransportError{}} =
             Integration.request(scope, %{operation: "transport.fail"},
               url: "https://example.test/fail",
               plug: {Req.Test, __MODULE__}
             )

    assert {:ok, %{entries: entries}} = Integration.list_page(scope)
    assert Enum.sort(Enum.map(entries, & &1.outcome)) == ["connection_error", "http_error"]
  end

  test "inbound metadata uses sealed actor and ordinary connection identifiers", %{
    scope: scope,
    system: system
  } do
    grant(system, @list)

    assert {:ok, id} =
             Integration.record_incoming(scope, %{
               operation: "company.update",
               endpoint: "/api/companies/8?token=secret",
               method: "PATCH",
               response_status: 403,
               duration_ms: 17,
               person_id: 999,
               tenant_id: 99,
               agent_id: "agent-a",
               connection_id: "connection-a",
               run_id: "run-a",
               request_body: %{token: "secret"}
             })

    assert {:ok, row} = Integration.get_exchange(scope, id)
    assert row.direction == "incoming"
    assert row.person_id == 7 and row.tenant_id == 1
    assert row.run_id == "run-a" and row.agent_id == "agent-a"
    assert row.outcome == "http_error" and row.duration_ms == 17

    assert {:ok, %{entries: [^row]}} =
             Integration.list_page(scope,
               direction: "incoming",
               actor: "agent-a",
               search: "company",
               status: "http_error",
               http_status: "403"
             )

    assert {:ok, %{entries: []}} =
             Integration.list_page(scope, direction: "incoming", since: ~U[2999-01-01 00:00:00Z])

    assert {:ok, %{entries: []}} =
             Integration.list_page(scope, direction: "incoming", http_status: "200")
  end

  test "list, payload and deletion grants are independent and rechecked", %{
    scope: scope,
    system: system
  } do
    {:ok, id} = Integration.record_incoming(scope, %{operation: "read"})
    assert {:error, :forbidden} = Integration.get_exchange(scope, id)
    grant(system, @list)
    assert {:ok, row} = Integration.get_exchange(scope, id)
    assert row.method == nil and row.duration_ms == nil and row.outcome == "unknown"
    assert {:error, :forbidden} = Integration.payload(scope, id)
    assert {:error, :forbidden} = Integration.delete_exchange(scope, id)
    grant(system, @payload)
    assert {:ok, _} = Integration.payload(scope, id)
    grant(system, @delete)
    {:ok, :stored} = Authz.put_principal_capability(system, 10, :user, 7, @delete, false)
    assert {:error, :forbidden} = Integration.delete_exchange(scope, id)
    assert {:ok, _} = Integration.get_exchange(scope, id)
  end

  test "ordinary tenants cannot read or delete foreign or tenantless exchanges", %{
    scope: scope,
    system: system
  } do
    for key <- [@list, @payload, @delete], do: grant(system, key)

    {:ok, foreign} =
      Integration.record_incoming(TenancyFixtures.scope(2), %{operation: "foreign"})

    Req.Test.expect(__MODULE__, &Req.Test.text(&1, "ok"))

    {:ok, _} =
      Integration.request_system(%{operation: "system"},
        url: "https://example.test/",
        plug: {Req.Test, __MODULE__}
      )

    anonymous = Repo.one!(from(e in Exchange, where: is_nil(e.tenant_id)))

    for id <- [foreign, anonymous.id] do
      assert {:error, :not_found} = Integration.get_exchange(scope, id)
      assert {:error, :not_found} = Integration.payload(scope, id)
      assert {:error, :not_found} = Integration.delete_exchange(scope, id)
    end

    operator = Authentication.sign_in(TenancyFixtures.scope(1, true), 7, 10)
    assert {:ok, _} = Integration.get_exchange(operator, foreign)
    assert {:ok, %{entries: [_]}} = Integration.list_page(operator)
    assert {:ok, %{entries: []}} = Integration.list_page(scope)
  end

  test "mandatory recursive redaction bounds previews and omits opaque bodies", %{
    scope: scope,
    system: system
  } do
    for key <- [@list, @payload], do: grant(system, key)

    {:ok, id} =
      Integration.record_incoming(scope, %{
        operation: "preview",
        retain_payload: true,
        request_headers: %{
          "AUTHORIZATION" => "secret",
          "x-api-key" => "secret",
          "Cookie" => "secret"
        },
        request_body: %{
          "nested" => [%{"refresh_token" => "secret", "clientSecret" => "secret", "count" => 3}]
        },
        response_body: "raw secret"
      })

    row = Repo.get!(Exchange, id)
    encoded = Jason.encode!(Map.take(row, [:request_body, :response_body, :request_headers]))
    refute encoded =~ "raw secret"

    assert row.request_body["value"]["nested"] == [
             %{"refresh_token" => "[redacted]", "clientSecret" => "[redacted]", "count" => 3}
           ]

    assert row.response_body == %{"kind" => "omitted", "reason" => "unstructured"}
    assert Redaction.structured(Enum.to_list(1..20_000))["reason"] == "size_limit"
    assert {:ok, payload} = Integration.payload(scope, id)
    refute Jason.encode!(payload) =~ ":secret"
    assert payload.response_body == %{"kind" => "omitted", "reason" => "unstructured"}
    assert %{"kind" => "json", "value" => %{"nested" => [nested]}} = payload.request_body

    assert nested == %{
             "refresh_token" => "[redacted]",
             "clientSecret" => "[redacted]",
             "count" => 3
           }

    assert payload.request_headers["kind"] == "json"
    assert payload.request_headers["value"]["AUTHORIZATION"] == "[redacted]"
    assert payload.metadata == nil
  end

  test "stored payloads keep trusted markers and re-redact everything else" do
    size_limit = %{"kind" => "omitted", "reason" => "size_limit"}
    assert Redaction.inspect_stored(size_limit) == size_limit

    assert Redaction.inspect_stored(%{"kind" => "json", "value" => %{"token" => "x", "n" => 1}}) ==
             %{"kind" => "json", "value" => %{"token" => "[redacted]", "n" => 1}}

    assert Redaction.inspect_stored(%{"kind" => "omitted", "reason" => "Bearer abc"}) ==
             %{"kind" => "[omitted]", "reason" => "[omitted]"}

    assert Redaction.inspect_stored(%{"kind" => "json", "value" => 1, "token" => "x"}) ==
             %{"kind" => "[omitted]", "value" => 1, "token" => "[redacted]"}

    assert Redaction.inspect_stored(%{"password" => "x", "note" => "raw"}) ==
             %{"password" => "[redacted]", "note" => "[omitted]"}

    assert Redaction.inspect_stored(nil) == nil
  end

  test "configured retention clears previews and leaves recent payloads and all metadata", %{
    scope: scope
  } do
    {:ok, old} =
      Integration.record_incoming(scope, %{
        operation: "old",
        retain_payload: true,
        request_body: %{count: 1}
      })

    {:ok, recent} =
      Integration.record_incoming(scope, %{
        operation: "recent",
        retain_payload: true,
        request_body: %{count: 2}
      })

    Repo.update_all(from(e in Exchange, where: e.id == ^old),
      set: [occurred_at: ~N[2026-01-01 00:00:00]]
    )

    assert Settings.get("integration.payload_retention_days") == 30
    assert Integration.prune_payloads(~N[2026-02-01 00:00:00]) == 1
    assert is_nil(Repo.get!(Exchange, old).request_body)
    assert Repo.get!(Exchange, old).operation == "old"
    refute is_nil(Repo.get!(Exchange, recent).request_body)
    assert Integration.prune_payloads(~N[2026-02-01 00:00:00]) == 0
  end

  test "unresolved incoming credentials stay operator-only without asserting a person", %{
    scope: scope,
    system: system
  } do
    grant(system, @list)

    {:ok, id} =
      Integration.record_incoming_system(%{
        operation: "authentication.refused",
        response_status: 401,
        person_id: 7,
        tenant_id: 1,
        agent_id: 42
      })

    assert {:error, :not_found} = Integration.get_exchange(scope, id)
    operator = Authentication.sign_in(TenancyFixtures.scope(1, true), 7, 10)
    assert {:ok, row} = Integration.get_exchange(operator, id)
    assert row.tenant_id == nil and row.person_id == nil and row.agent_id == "42"
    assert {:error, changeset} = Integration.record_incoming(scope, %{duration_ms: -1})
    refute changeset.valid?

    assert_raise FunctionClauseError, fn ->
      Integration.record_incoming(Bilimbi.Base.Database.TestHelpers.opaque(1), %{})
    end
  end

  test "retention follows the operator setting and runs through Schedule", %{scope: scope} do
    {:ok, id} =
      Integration.record_incoming(scope, %{
        operation: "retained",
        retain_payload: true,
        request_body: %{count: 1}
      })

    Repo.update_all(from(e in Exchange, where: e.id == ^id),
      set: [occurred_at: ~N[2026-01-20 00:00:00]]
    )

    assert Integration.prune_payloads(~N[2026-02-01 00:00:00]) == 0
    assert {:ok, 10} = Settings.put("integration.payload_retention_days", 10)
    assert Integration.prune_payloads(~N[2026-02-01 00:00:00]) == 1
    assert is_nil(Repo.get!(Exchange, id).request_body)
    assert {:ok, %{}} = Bilimbi.Base.Integration.RetentionWorker.validate_scheduled_args(%{})

    assert {:error, :invalid_args} =
             Bilimbi.Base.Integration.RetentionWorker.validate_scheduled_args(%{"days" => 1})

    assert :ok = Bilimbi.Base.Integration.RetentionWorker.handle_scheduled_job(%{}, nil)
  end

  test "manual deletion is audited without copying protected payloads", %{
    scope: scope,
    system: system
  } do
    grant(system, @delete)

    {:ok, id} =
      Integration.record_incoming(scope, %{
        operation: "delete",
        retain_payload: true,
        request_body: %{count: 2}
      })

    assert :ok = Integration.delete_exchange(scope, id)

    assert {:ok, [mutation]} =
             Audit.list_subject_mutations(scope, Exchange.__audit_auditable_type__(), id)

    assert mutation.event == "deleted"
    assert mutation.old_values["request_body"] == "[redacted]"
    assert mutation.old_values["metadata"] == "[redacted]"
    refute Repo.get(Exchange, id)
  end
end
