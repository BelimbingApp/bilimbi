defmodule BilimbiWeb.CompanyEmployeesPanelTest do
  @moduledoc """
  The company show page renders its Employees section through the
  `core/employee`-owned `"company.employees"` discovered embed (#595), so this
  covers the populated case the module boundary now owns. The empty case lives
  with the rest of the page in `company_live_test.exs`.
  """
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Bilimbi Industries"})
    # `log_in_as/1` rehydrates the signed-in user (id 91, company 73), so it
    # must exist before the page mounts.
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "Grace Hopper",
        designation: "Rear Admiral"
      })

    :ok
  end

  test "lists the company's employees through the discovered panel", %{conn: conn} do
    grant_capabilities!(["admin.company.list", "admin.company.view"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

    # The section is owned by core/employee and rendered by manifest key; the
    # company page never names the module.
    assert has_element?(view, "#company-employees-table td", "Grace Hopper")
    assert has_element?(view, "#company-employees-table td", "EMP-001")
    refute has_element?(view, "#company-employees-table-empty")
  end
end
