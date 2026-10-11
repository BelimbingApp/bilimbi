defmodule Bilimbi.Core.EmployeeArchivedCompanyTest do
  @moduledoc """
  An archived company's employees and employee types are read-only: every
  Core Employee write into it, and the affiliation lock a sibling workflow
  takes, is `:company_archived`, while the reads keep answering.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee

  import Bilimbi.Core.Employee.TestFixtures

  @archived 74

  setup do
    create_employee_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Active", code: "active"})

    CompanyFixtures.insert_company!(%{
      id: @archived,
      tenant_id: 41,
      name: "Archived",
      code: "archived",
      status: "archived"
    })

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "an employee cannot be created, changed, deleted or linked in it", %{scope: scope} do
    assert {:error, :company_archived} =
             Employee.create_employee(scope, @archived, %{
               employee_number: "EMP-9",
               full_name: "Nobody"
             })

    assert {:error, :company_archived} =
             Employee.update_employee(scope, @archived, 1, %{full_name: "Renamed"})

    assert {:error, :company_archived} = Employee.delete_employee(scope, @archived, 1)
    assert {:error, :company_archived} = Employee.assign_subordinate(scope, @archived, 1, 2)

    assert {:error, :company_archived} =
             Employee.create_employee_type(scope, @archived, %{code: "x", label: "X"})

    assert {:ok, {:error, :company_archived}} =
             Repo.transaction(fn -> Employee.lock_affiliation(scope, @archived, 1) end)
  end

  test "its employees stay readable", %{scope: scope} do
    assert {:ok, []} = Employee.list_employees(scope, @archived)
    assert {:ok, _types} = Employee.list_employee_types(scope, @archived)
  end
end
