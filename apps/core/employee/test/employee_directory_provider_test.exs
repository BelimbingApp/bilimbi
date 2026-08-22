defmodule Bilimbi.Core.Employee.EmployeeDirectoryProviderTest do
  @moduledoc """
  The `:employee` half of the directory (ADR 0014), against the real database.

  Shares its resolution path (`get_tenant_employees/2`) with the `:agent`
  provider, so the archived-company and search behaviours proven in
  `PrincipalDirectoryProviderTest` are not repeated; what this proves is that the
  `:employee` kind names *any* employee (not only agents) inside the tenant, and
  keeps the boundary.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.EmployeeDirectoryProvider, as: Provider

  setup do
    Employee.TestFixtures.create_employee_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant 41"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.insert_company!(%{id: 76, tenant_id: 41, name: "Sibling", code: "sibling"})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant 42"})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 42, name: "Other", code: "other"})

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)
    {:ok, other_scope} = Tenancy.scope(42)

    # A plain full_time employee — no agent — is exactly the case the `:agent`
    # provider cannot name and this one must (a department Head).
    {:ok, mine} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "Ada Lovelace",
        employee_type: "full_time"
      })

    {:ok, theirs} =
      Employee.create_employee(other_scope, 74, %{
        employee_number: "EMP-002",
        full_name: "Grace Hopper",
        employee_type: "full_time"
      })

    %{scope: scope, other_scope: other_scope, mine: mine, theirs: theirs}
  end

  test "answers for the :employee kind" do
    assert Provider.principal_kind() == :employee
  end

  test "names a non-agent employee inside the scope's tenant", %{scope: scope, mine: mine} do
    assert Provider.names(scope, [mine.id]) == %{mine.id => "Ada Lovelace"}
  end

  test "the tenant boundary is symmetric", %{
    scope: scope,
    other_scope: other,
    mine: mine,
    theirs: theirs
  } do
    assert Provider.names(scope, [theirs.id]) == %{}
    assert Provider.names(other, [mine.id]) == %{}
    assert Provider.names(other, [theirs.id]) == %{theirs.id => "Grace Hopper"}
  end

  test "resolves only the visible half of a mixed request", %{
    scope: scope,
    mine: mine,
    theirs: theirs
  } do
    assert Provider.names(scope, [mine.id, theirs.id]) == %{mine.id => "Ada Lovelace"}
  end

  test "an id that exists nowhere is absent, and an empty request is an empty map", %{
    scope: scope
  } do
    assert Provider.names(scope, [404]) == %{}
    assert Provider.names(scope, []) == %{}
  end

  test "lists only employees who currently belong to the selected company", %{
    scope: scope,
    mine: mine
  } do
    {:ok, sibling} =
      Employee.create_employee(scope, 76, %{
        employee_number: "EMP-003",
        full_name: "Katherine Johnson",
        employee_type: "full_time"
      })

    assert Provider.candidate_ids(scope, %{company_id: 73}) == [mine.id]
    assert Provider.candidate_ids(scope, %{company_id: 76}) == [sibling.id]
    assert Provider.candidate_ids(scope, %{company_id: 999}) == []
  end
end
