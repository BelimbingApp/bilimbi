defmodule BilimbiWeb.AgentPlansTest do
  use BilimbiWeb.ConnCase, async: true
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{AgentApi, Authz, Repo, Settings, Tenancy}
  alias Bilimbi.Base.AgentApi.Plan
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.{AgentAccess, Company, Employee}

  setup do
    signed_in_identity!()
    AgentApi.TestFixtures.create_plan_tables!()
    AgentAccess.TestFixtures.create_tables!()
    Bilimbi.Base.Integration.TestFixtures.create_exchanges_table!()

    grant_capabilities!(
      ~w(admin.company.create admin.company.list admin.company.view admin.employee.create admin.employee.list admin.company.tenant-wide.manage)
    )

    {:ok, tenant} = Tenancy.scope(41)
    scope = Authentication.sign_in(tenant, 91, 73)
    :ok = Employee.ensure_system_types()
    %{scope: scope, tokens: tokens(scope)}
  end

  defp tokens(scope) do
    {:ok, device} = AgentAccess.start_device(AgentAccess.client_id(), "codex/test-high")

    :ok =
      AgentAccess.decide(
        scope,
        device.user_code,
        :approve,
        DateTime.add(DateTime.utc_now(), 86_400)
      )

    {:ok, tokens} = AgentAccess.exchange(AgentAccess.client_id(), device.device_code)
    tokens
  end

  defp bearer(conn, tokens) do
    conn
    |> recycle()
    |> put_req_header("authorization", "Bearer " <> tokens.access_token)
    |> put_req_header("x-bilimbi-agent-id", "codex/test-high")
    |> put_req_header("x-bilimbi-run-id", "safe-write-test")
  end

  defp company(name \\ "New supplier"),
    do: %{
      "key" => "core.company.create",
      "input" => %{"name" => name, "email" => "supplier@example.test"}
    }

  defp employee(company_id),
    do: %{
      "key" => "core.employee.create",
      "input" => %{
        "employer_company_id" => company_id,
        "full_name" => "Contact Person",
        "employee_number" => "CONTACT-1",
        "designation" => "Sales"
      }
    }

  defp preview(conn, tokens, operations),
    do:
      conn
      |> bearer(tokens)
      |> post("/api/v1/plans", %{operations: operations})
      |> json_response(200)

  defp commit(conn, tokens, code, operations),
    do:
      conn
      |> bearer(tokens)
      |> post("/api/v1/plans/commit", %{plan_code: code, operations: operations})

  test "dry run shows domain defaults, commits once, returns URLs and records both calls and mutations",
       %{conn: conn, tokens: tokens, scope: scope} do
    operations = [company(), employee(73)]
    before = Repo.aggregate(Bilimbi.Core.Company.Schema, :count)
    plan = preview(conn, tokens, operations)
    assert plan["valid"]
    assert Repo.aggregate(Bilimbi.Core.Company.Schema, :count) == before

    assert Enum.any?(
             hd(plan["results"])["preview"]["changes"],
             &(&1 == %{"field" => "code", "from" => nil, "to" => "new_supplier"})
           )

    assert Repo.one!(Plan).id != plan["plan_code"]
    report = commit(conn, tokens, plan["plan_code"], operations) |> json_response(200)
    [company, person] = report["results"]
    assert company["url"] == BilimbiWeb.Endpoint.url() <> "/companies/#{company["record"]["id"]}"
    assert person["url"] == BilimbiWeb.Endpoint.url() <> "/employees/#{person["record"]["id"]}"
    assert {:ok, %{name: "New supplier"}} = Company.get_company(scope, company["record"]["id"])

    assert {:ok, %{full_name: "Contact Person"}} =
             Employee.get_employee(scope, 73, person["record"]["id"])

    assert commit(conn, tokens, plan["plan_code"], operations) |> json_response(409) == %{
             "error" => "plan_already_used"
           }

    for item <- report["results"] do
      id = to_string(item["record"]["id"])

      type =
        if item["key"] == "core.company.create",
          do: "Bilimbi.Core.Company.Schema",
          else: "Bilimbi.Core.Employee.Schema"

      mutation =
        Repo.one!(
          from(m in Bilimbi.Base.Audit.MutationSchema,
            where: m.auditable_id == ^id and m.auditable_type == ^type and m.event == "created"
          )
        )

      assert mutation.actor_type == "user"
      assert mutation.actor_id == 91
      assert mutation.tenant_id == 41
    end

    logs =
      Repo.all(
        from(e in Bilimbi.Base.Integration.Exchange,
          where: e.path in ["/api/v1/plans", "/api/v1/plans/commit"]
        )
      )

    assert length(logs) == 3

    assert Enum.all?(
             logs,
             &(&1.person_id == 91 and &1.run_id == "safe-write-test" and is_nil(&1.request_body) and
                 is_nil(&1.response_body))
           )
  end

  test "exact input and operation order are bound to the code", %{conn: conn, tokens: tokens} do
    operations = [company(), company("Second supplier")]
    plan = preview(conn, tokens, operations)

    for changed <- [[company("Tampered")], Enum.reverse(operations), [company()]] do
      assert commit(conn, tokens, plan["plan_code"], changed) |> json_response(409) == %{
               "error" => "plan_mismatch"
             }
    end

    assert is_nil(Repo.one!(Plan).used_at)
    assert commit(conn, tokens, plan["plan_code"], operations) |> json_response(200)
  end

  test "expiry and connection identity are bound without trusting the stated agent ID", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    operations = [company()]
    plan = preview(conn, tokens, operations)
    other_connection = tokens(scope)

    assert commit(conn, other_connection, plan["plan_code"], operations) |> json_response(409) ==
             %{"error" => "plan_mismatch"}

    Repo.one!(Plan)
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -1)
    )
    |> Repo.update!()

    assert commit(conn, tokens, plan["plan_code"], operations) |> json_response(409) == %{
             "error" => "plan_expired"
           }
  end

  test "a new dry run deletes plans that expired more than a day ago", %{
    conn: conn,
    tokens: tokens
  } do
    old = preview(conn, tokens, [company("Old supplier")])
    recent = preview(conn, tokens, [company("Recent supplier")])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for {plan, offset} <- [{old, -90_000}, {recent, -3_600}] do
      id =
        :crypto.hash(:sha256, :erlang.term_to_binary(plan["plan_code"]))
        |> Base.encode16(case: :lower)

      Repo.get!(Plan, id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(now, offset))
      |> Repo.update!()
    end

    fresh = preview(conn, tokens, [company("Fresh supplier")])
    assert Repo.aggregate(Plan, :count) == 2

    assert commit(conn, tokens, old["plan_code"], [company("Old supplier")]) |> json_response(409) ==
             %{"error" => "invalid_plan_code"}

    assert fresh["plan_code"] != recent["plan_code"]
  end

  test "another person cannot use a plan", %{scope: scope} do
    Bilimbi.Core.User.TestFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      email: "other@example.test"
    })

    grant_capabilities!("admin.company.create", user_id: 92)
    {:ok, tenant} = Tenancy.scope(41)
    other = Authentication.sign_in(tenant, 92, 73)
    operations = [company()]
    {:ok, plan} = AgentApi.plan(scope, operations)
    assert AgentApi.commit(other, plan["plan_code"], operations) == {:error, :plan_mismatch}
  end

  test "authorization and the company switch are checked again at commit", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    operations = [company()]
    plan = preview(conn, tokens, operations)
    {:ok, _} = Settings.put("authz.agent_writes_enabled", false, Settings.Scope.company(73, 41))

    assert %{"valid" => false, "results" => [%{"error" => %{"code" => "writes_not_enabled"}}]} =
             preview(conn, tokens, operations)

    assert %{"error" => "plan_rejected"} =
             commit(conn, tokens, plan["plan_code"], operations) |> json_response(422)

    {:ok, _} = Settings.put("authz.agent_writes_enabled", true, Settings.Scope.company(73, 41))

    {:ok, :stored} =
      Authz.put_principal_capability(scope, 73, :user, 91, "admin.company.create", false)

    assert %{"error" => "plan_rejected", "results" => [%{"error" => %{"code" => "forbidden"}}]} =
             commit(conn, tokens, plan["plan_code"], operations) |> json_response(422)

    assert is_nil(Repo.one!(Plan).used_at)
  end

  test "validation, identity injection and restricted fields never issue a code", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    grant_capabilities!("admin.authz.field.manage")

    {:ok, role} =
      Authz.create_role(scope, 73, %{name: "Restricted writer", code: "restricted_writer"})

    {:ok, _} = Authz.put_field_restriction(scope, "companies", "email", [role.id])
    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    operations = [
      company(),
      %{"key" => "core.company.create", "input" => %{"name" => "", "tenant_id" => 42}}
    ]

    plan = preview(conn, tokens, operations)
    refute plan["valid"]
    refute Map.has_key?(plan, "plan_code")
    [restricted, injected] = plan["results"]
    assert Map.has_key?(restricted["error"]["fields"], "email")
    assert Map.has_key?(injected["error"]["fields"], "tenant_id")
    refute Repo.exists?(Plan)
  end

  test "external employer targets use the form's company permission and target switch", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    {:ok, external} = Company.create_company(scope, %{name: "External employer"})
    operations = [employee(external.id)]
    plan = preview(conn, tokens, operations)
    assert plan["valid"]

    {:ok, _} =
      Settings.put("authz.agent_writes_enabled", false, Settings.Scope.company(external.id, 41))

    refute preview(conn, tokens, operations)["valid"]

    {:ok, _} =
      Settings.put("authz.agent_writes_enabled", true, Settings.Scope.company(external.id, 41))

    {:ok, :stored} =
      Authz.put_principal_capability(
        scope,
        73,
        :user,
        91,
        "admin.company.tenant-wide.manage",
        false
      )

    refute preview(conn, tokens, operations)["valid"]

    {:ok, :stored} =
      Authz.put_principal_capability(
        scope,
        73,
        :user,
        91,
        "admin.company.tenant-wide.manage",
        true
      )

    assert %{
             "results" => [
               %{"record" => %{"company_id" => company_id, "id" => employee_id}, "url" => url}
             ]
           } =
             commit(conn, tokens, plan["plan_code"], operations) |> json_response(200)

    assert company_id == external.id
    grant_capabilities!(["admin.employee.view", "admin.employee.update"])
    target = URI.parse(url)
    path = target.path <> "?" <> target.query
    {:ok, view, _} = conn |> log_in_as() |> live(path)
    assert has_element?(view, "h1", "Contact Person")

    Bilimbi.Core.User.TestFixtures.insert_user!(%{
      id: 92,
      company_id: external.id,
      name: "External account",
      email: "external@example.test"
    })

    {:ok, panel_view, _} = conn |> log_in_as() |> live(path)

    {:ok, :stored} =
      Authz.put_principal_capability(
        scope,
        73,
        :user,
        91,
        "admin.company.tenant-wide.manage",
        false
      )

    render_hook(view, "save_field", %{
      "id" => to_string(employee_id),
      "full_name" => "Unauthorized edit"
    })

    assert_redirect(view, "/employees")

    assert {:ok, %{full_name: "Contact Person"}} =
             Employee.get_employee(scope, external.id, employee_id)

    panel_view |> element("#employee-user-form") |> render_change(%{"user_id" => "92"})
    assert_redirect(panel_view, "/employees")
    assert {:ok, %{employee_id: nil}} = Bilimbi.Core.User.get_user(scope, external.id, 92)
    assert {:error, {:live_redirect, %{to: "/employees"}}} = conn |> log_in_as() |> live(path)
  end

  test "a plan rolls back every write and audit if a later operation fails", %{
    conn: conn,
    tokens: tokens
  } do
    operations = [company(), company()]
    plan = preview(conn, tokens, operations)
    before = Repo.aggregate(Bilimbi.Core.Company.Schema, :count)

    assert %{"error" => "plan_rejected"} =
             commit(conn, tokens, plan["plan_code"], operations) |> json_response(422)

    assert Repo.aggregate(Bilimbi.Core.Company.Schema, :count) == before
    assert is_nil(Repo.one!(Plan).used_at)

    refute Repo.exists?(
             from(m in Bilimbi.Base.Audit.MutationSchema,
               where: fragment("?->>'name'", m.new_values) == "New supplier"
             )
           )
  end

  test "field restrictions introduced after review refuse commit", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    operations = [company()]
    plan = preview(conn, tokens, operations)
    grant_capabilities!("admin.authz.field.manage")
    {:ok, role} = Authz.create_role(scope, 73, %{name: "Restricted", code: "restricted"})
    {:ok, _} = Authz.put_field_restriction(scope, "companies", "email", [role.id])
    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    assert %{
             "error" => "plan_rejected",
             "results" => [%{"error" => %{"fields" => %{"email" => _}}}]
           } =
             commit(conn, tokens, plan["plan_code"], operations) |> json_response(422)

    assert is_nil(Repo.one!(Plan).used_at)
  end

  test "a valid but changed preview needs a fresh plan", %{
    conn: conn,
    tokens: tokens,
    scope: scope
  } do
    operations = [company()]
    plan = preview(conn, tokens, operations)
    grant_capabilities!("admin.authz.field.manage")
    {:ok, role} = Authz.create_role(scope, 73, %{name: "Tax restricted", code: "tax_restricted"})
    {:ok, _} = Authz.put_field_restriction(scope, "companies", "tax_id", [role.id])
    {:ok, :assigned} = Authz.assign_role(scope, 73, :user, 91, role.id)

    assert commit(conn, tokens, plan["plan_code"], operations) |> json_response(409) == %{
             "error" => "stale_plan"
           }

    assert is_nil(Repo.one!(Plan).used_at)
  end

  test "write input never becomes authenticated identity and reserved people are refused", %{
    conn: conn,
    tokens: tokens
  } do
    for input <- [
          Map.put(employee(73)["input"], "employee_number", "SYS-001"),
          Map.put(employee(73)["input"], "employee_type", "not-a-type"),
          Map.put(employee(73)["input"], "user_id", 92),
          Map.put(employee(73)["input"], "employer_company_id", 999_999)
        ] do
      result = preview(conn, tokens, [%{"key" => "core.employee.create", "input" => input}])
      refute result["valid"]
      refute Map.has_key?(result, "plan_code")
    end

    assert %{"valid" => false, "results" => [%{"error" => %{"code" => "writes_not_enabled"}}]} =
             preview(conn, tokens, [%{"key" => "core.company.list", "input" => %{}}])

    assert conn
           |> bearer(tokens)
           |> post("/api/v1/plans", %{operations: List.duplicate(company(), 21)})
           |> json_response(422)
  end
end
