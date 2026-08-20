defmodule Bilimbi.Core.Employee.PrincipalDirectoryProviderTest do
  @moduledoc """
  The `:agent` half of ADR 0011's seam, against the real database.

  `apps/base/principal_directory` can only test the contract on doubles. This is
  where the tenant boundary and the deliberate archived-company visibility are
  proved.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.PrincipalDirectoryProvider, as: Provider
  alias Ecto.Adapters.SQL

  setup do
    Employee.TestFixtures.create_employee_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant 41"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant 42"})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Other Company",
      code: "other_company"
    })

    :ok = Employee.ensure_system_types()

    {:ok, scope} = Tenancy.scope(41)
    {:ok, other_scope} = Tenancy.scope(42)

    {:ok, mine} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "Ada Lovelace",
        email: "ada.employee@example.test"
      })

    {:ok, theirs} =
      Employee.create_employee(other_scope, 74, %{
        employee_number: "EMP-002",
        full_name: "Grace Hopper",
        email: "grace.employee@example.test"
      })

    %{scope: scope, other_scope: other_scope, mine: mine, theirs: theirs}
  end

  test "answers for the :agent kind" do
    assert Provider.principal_kind() == :agent
  end

  test "names an employee inside the scope's tenant", %{scope: scope, mine: mine} do
    assert Provider.names(scope, [mine.id]) == %{mine.id => "Ada Lovelace"}
  end

  test "returns nothing for an employee in another tenant", %{scope: scope, theirs: theirs} do
    assert Provider.names(scope, [theirs.id]) == %{}
  end

  test "resolves only the visible half of a mixed request", %{
    scope: scope,
    mine: mine,
    theirs: theirs
  } do
    assert Provider.names(scope, [mine.id, theirs.id]) == %{mine.id => "Ada Lovelace"}
  end

  # Both directions: a one-sided assertion passes as an accident of one tenant's
  # data rather than as a boundary.
  test "the boundary is symmetric", %{other_scope: other, mine: mine, theirs: theirs} do
    assert Provider.names(other, [theirs.id]) == %{theirs.id => "Grace Hopper"}
    assert Provider.names(other, [mine.id]) == %{}
  end

  # The moduledoc claims a grant outlives its subject's company being archived,
  # so the name must survive too. Asserting it rather than only writing it down:
  # `get_employee/2` uses the live-company list and would fail this, which is the
  # difference the moduledoc is describing.
  test "still names an employee whose company was archived after the fact", %{
    scope: scope,
    mine: mine
  } do
    SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-20 12:00:00' WHERE id = $1",
      [73]
    )

    assert Provider.names(scope, [mine.id]) == %{mine.id => "Ada Lovelace"}
    assert {:error, :employee_not_found} = Employee.get_employee(scope, mine.id)
  end

  test "an id that exists nowhere is absent rather than an error", %{scope: scope} do
    assert Provider.names(scope, [404]) == %{}
  end

  test "an empty request is an empty map", %{scope: scope} do
    assert Provider.names(scope, []) == %{}
  end
end
