defmodule BilimbiWeb.AgentApiTest do
  @moduledoc """
  The real agent API registry, as the host boots it: every installed
  module's operations stand on registered capabilities, and a person finds
  the Core operations by words and calls them with the same capability
  checks and field restrictions the Companies and Employees pages apply.
  """

  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.AgentApi
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      jurisdiction: "MY",
      email: "hq@example.com"
    })

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Retail",
      code: "bilimbi_retail",
      parent_id: 73
    })

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere Ltd",
      code: "elsewhere"
    })

    CompanyFixtures.assign_primary_company!(41, 73)

    for {id, name} <- [{91, "Ada Lovelace"}, {92, "Grace Hopper"}, {96, "Narrow Reader"}] do
      UserFixtures.insert_user!(%{
        id: id,
        company_id: 73,
        name: name,
        email: "user#{id}@example.com"
      })
    end

    grant_capabilities!(~w(admin.company.list admin.company.view admin.employee.list))
    grant_capabilities!(~w(admin.company.list), user_id: 96)
    :ok = Employee.ensure_system_types()

    %{scope: sign_in(91), narrow: sign_in(96)}
  end

  defp sign_in(user_id) do
    {:ok, tenant_scope} = Tenancy.scope(41)
    Authentication.sign_in(tenant_scope, user_id, 73)
  end

  test "every installed operation and guide stands on a registered capability" do
    registry = ContributionRegistry.consumer!(:agent_api)
    capabilities = MapSet.new(Authz.capabilities())

    for {key, entry} <- Map.merge(registry.operations, registry.guides) do
      assert MapSet.member?(capabilities, entry.capability),
             "#{key} stands on #{entry.capability}, which no installed module registers"
    end

    assert Map.has_key?(registry.operations, "core.company.list")
    assert Map.has_key?(registry.operations, "core.company.get")
    assert Map.has_key?(registry.operations, "core.employee.list")
  end

  test "searching for companies ranks the company list first", %{scope: scope} do
    assert [%{key: "core.company.list", disposition: :call} | _rest] =
             AgentApi.search(scope, "find companies")

    assert [%{key: "core.employee.list"} | _rest] = AgentApi.search(scope, "list staff")
  end

  test "a person without the company page's capability neither finds nor reads a company", %{
    narrow: narrow
  } do
    found = narrow |> AgentApi.search("company") |> Enum.map(& &1.key)
    assert "core.company.list" in found
    refute "core.company.get" in found

    assert AgentApi.call(narrow, "core.company.get", %{"company_id" => 73}) ==
             {:error, {:forbidden, :missing_capability}}

    assert {:ok, %{"result" => [_ | _]}} = AgentApi.call(narrow, "core.company.list", %{})
  end

  test "a company reads as the person sees it, inside their tenant only", %{scope: scope} do
    assert {:ok, %{"result" => company}} =
             AgentApi.call(scope, "core.company.get", %{"company_id" => 73})

    assert %{"id" => 73, "name" => "Bilimbi Industries", "jurisdiction" => "MY"} = company

    assert AgentApi.call(scope, "core.company.get", %{"company_id" => 75}) ==
             {:error, :not_found}
  end

  test "a field an operator restricted reads as restricted, in a read and in a list", %{
    scope: scope
  } do
    grant_capabilities!("admin.authz.field.manage", user_id: 92)
    operator = sign_in(92)
    {:ok, finance} = Authz.create_role(operator, 73, %{name: "Finance", code: "finance"})
    {:ok, _} = Authz.put_field_restriction(operator, "companies", "jurisdiction", [finance.id])

    assert {:ok, %{"result" => company}} =
             AgentApi.call(scope, "core.company.get", %{"company_id" => 73})

    assert company["jurisdiction"] == %{"restricted" => true}
    assert company["email"] == "hq@example.com"

    assert {:ok, %{"result" => entries, "meta" => %{"page" => page}}} =
             AgentApi.call(scope, "core.company.list", %{"search" => "Industries"})

    assert [%{"id" => 73, "jurisdiction" => %{"restricted" => true}, "primary" => true}] = entries
    assert page == %{"page" => 1, "page_size" => 25, "total" => 1}
  end

  test "bad input is refused field by field", %{scope: scope} do
    assert AgentApi.call(scope, "core.company.get", %{}) ==
             {:error, {:invalid_input, %{"company_id" => ["is required"]}}}

    assert AgentApi.call(scope, "core.company.list", %{"status" => "closed", "page" => 0}) ==
             {:error,
              {:invalid_input,
               %{
                 "page" => ["must be at least 1"],
                 "status" => ["must be one of active, suspended, pending, archived"]
               }}}
  end

  test "employees are listed for the company the person signed in at", %{scope: scope} do
    {:ok, _} =
      Employee.create_employee(scope, 73, %{
        full_name: "Boss Person",
        employee_number: "E-1",
        status: "active"
      })

    assert {:ok, %{"result" => [employee], "meta" => %{"page" => %{"total" => 1}}}} =
             AgentApi.call(scope, "core.employee.list", %{"search" => "boss"})

    assert %{"full_name" => "Boss Person", "employee_number" => "E-1"} = employee
  end
end
