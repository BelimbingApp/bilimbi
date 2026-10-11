defmodule Bilimbi.Core.AddressArchivedCompanyTest do
  @moduledoc """
  An archived company's address attachments, and those of its employees,
  are read-only: Core Address refuses them with `:company_archived` and
  keeps the attached addresses readable. An address such a company or
  employee links to is part of that record, so its own facts are frozen too.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.TestFixtures, as: EmployeeFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures

  import Bilimbi.Core.Address.TestFixtures

  @active 73
  @archived 74

  setup do
    EmployeeFixtures.create_employee_tables!()
    AuthzFixtures.create_authz_tables!()
    GeonamesFixtures.create_geonames_tables!()
    create_address_tables!()
    GeonamesFixtures.insert_country!()
    GeonamesFixtures.insert_admin1!()

    TenancyFixtures.insert_tenant!(%{id: 41, name: "Operator"})
    CompanyFixtures.insert_company!(%{id: @active, tenant_id: 41, name: "Active", code: "a"})

    CompanyFixtures.insert_company!(%{
      id: @archived,
      tenant_id: 41,
      name: "Archived",
      code: "archived"
    })

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, @archived, %{employee_number: "EMP-1", full_name: "Kept"})

    {:ok, address} = Address.create_address(scope, %{label: "Head office"})

    {:ok, :attached} =
      Address.attach_to_company(scope, address.id, @archived, %{kind: ["billing"], priority: 1})

    {:ok, :attached} = Address.attach_to_employee(scope, address.id, employee.id, %{})

    archive!(@archived)

    %{scope: scope, address: address, employee: employee}
  end

  test "attachments to the company refuse to change", ctx do
    assert {:ok, [_attached]} = Address.list_company_addresses(ctx.scope, @archived)

    assert {:error, :company_archived} =
             Address.update_company_attachment(ctx.scope, ctx.address.id, @archived, %{
               priority: 2
             })

    assert {:error, :company_archived} =
             Address.detach_from_company(ctx.scope, ctx.address.id, @archived)

    assert {:error, :company_archived} =
             Address.create_and_attach_to_company(ctx.scope, @archived, %{label: "New"})

    {:ok, other} = Address.create_address(ctx.scope, %{label: "Other"})

    assert {:error, :company_archived} =
             Address.attach_to_company(ctx.scope, other.id, @archived, %{kind: ["billing"]})

    assert {:ok, [_attached]} = Address.list_company_addresses(ctx.scope, @archived)
  end

  test "attachments to its employees refuse to change", ctx do
    assert {:error, :company_archived} =
             Address.detach_from_employee(ctx.scope, ctx.address.id, ctx.employee.id)

    assert {:error, :company_archived} =
             Address.update_employee_attachment(ctx.scope, ctx.address.id, ctx.employee.id, %{
               priority: 3
             })

    {:ok, other} = Address.create_address(ctx.scope, %{label: "Other"})

    assert {:error, :company_archived} =
             Address.attach_to_employee(ctx.scope, other.id, ctx.employee.id, %{})

    assert {:ok, [_attached]} =
             Address.list_employee_attached_addresses(ctx.scope, ctx.employee.id)
  end

  test "an address linked to the company or its employees keeps its facts", ctx do
    assert {:error, :company_archived} =
             Address.update_address(ctx.scope, ctx.address.id, %{label: "Renamed"})

    assert {:ok, %{label: "Head office"}} = Address.get_address(ctx.scope, ctx.address.id)

    # Still linked through the employee alone.
    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "DELETE FROM addressables WHERE address_id = $1 AND addressable_type = $2",
      [ctx.address.id, Bilimbi.Core.Company.addressable_identity()]
    )

    assert {:error, :company_archived} =
             Address.update_address(ctx.scope, ctx.address.id, %{label: "Renamed"})

    {:ok, unlinked} = Address.create_address(ctx.scope, %{label: "Unlinked"})

    assert {:ok, %{label: "Renamed"}} =
             Address.update_address(ctx.scope, unlinked.id, %{label: "Renamed"})
  end

  # The records above were attached while the company was live; the status
  # is then flipped the way the lifecycle writes it, without the audit and
  # capability fixtures the lifecycle operation itself needs here.
  defp archive!(company_id) do
    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET status = 'archived' WHERE id = $1",
      [company_id]
    )
  end
end
