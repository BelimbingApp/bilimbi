defmodule BilimbiWeb.GridCatalogTest do
  @moduledoc """
  The real catalog, as the host boots it: every Core module's tables,
  fields and links validate together, and a person's scope walks them over
  the real Core tables with each owner's own boundary applied on every hop.
  """

  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @all ~w(admin.user.list admin.company.list admin.employee.list admin.employee-type.list
          admin.address.list admin.geonames.list)

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_departments_table!()
    CompanyFixtures.create_department_types_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Bilimbi Industries"})

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
    GeonamesFixtures.insert_country!(%{iso: "MY"})
    GeonamesFixtures.insert_country!(%{iso: "SG"})
    CompanyFixtures.insert_department!(1, 73)

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 93,
      company_id: 75,
      name: "Someone Else",
      email: "else@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 94,
      company_id: nil,
      name: "No Company",
      email: "none@example.com"
    })

    grant_capabilities!(@all)
    :ok = Employee.ensure_system_types()
    {:ok, tenant_scope} = Tenancy.scope(41)
    scope = Authentication.sign_in(tenant_scope, 91, 73)

    {:ok, boss} =
      Employee.create_employee(scope, 73, %{
        full_name: "Boss Person",
        employee_number: "E-1",
        email: "boss@example.com",
        department_id: 1,
        status: "active"
      })

    {:ok, report} =
      Employee.create_employee(scope, 73, %{
        full_name: "Report Person",
        employee_number: "E-2",
        supervisor_id: boss.id,
        status: "probation"
      })

    UserFixtures.insert_user!(%{
      id: 95,
      company_id: 73,
      employee_id: boss.id,
      name: "Boss Login",
      email: "boss.login@example.com"
    })

    {:ok, address} =
      Address.create_address(scope, %{
        label: "HQ",
        line1: "1 Main St",
        locality: "Kuala Lumpur",
        country_iso: "MY"
      })

    {:ok, second} =
      Address.create_address(scope, %{
        label: "Depot",
        line1: "2 Side St",
        locality: "Penang",
        country_iso: "MY"
      })

    AddressFixtures.insert_attachment!(%{
      address_id: address.id,
      addressable_type: Bilimbi.Core.Company.addressable_identity(),
      addressable_id: 73,
      is_primary: true
    })

    AddressFixtures.insert_attachment!(%{
      address_id: second.id,
      addressable_type: Bilimbi.Core.Company.addressable_identity(),
      addressable_id: 73
    })

    AddressFixtures.insert_attachment!(%{
      address_id: second.id,
      addressable_type: Bilimbi.Core.Employee.addressable_identity(),
      addressable_id: boss.id
    })

    %{scope: scope, catalog: Grid.catalog(scope), boss: boss, report: report}
  end

  # The walked cells of the rows with these keys, as a list page attaches
  # them to rows of its own: `%{key => %{column_id => value}}`.
  defp walk(catalog, table_id, specs, keys) do
    {:ok, table} = Grid.fetch_table(catalog, table_id)
    {:ok, columns} = Grid.resolve(catalog, table, specs)

    catalog
    |> Grid.attach(table, keys, columns)
    |> Map.new(fn {key, attached} -> {key, attached.cells} end)
  end

  defp tables(catalog, ids),
    do: Enum.filter(ids, &match?({:ok, _}, Grid.fetch_table(catalog, &1)))

  @tables ~w(addresses companies countries departments employee_types employees legal_entity_types users)

  test "the booted catalog offers every Core table to a fully granted account", %{
    catalog: catalog
  } do
    assert tables(catalog, @tables) == @tables
  end

  test "users walk to their company, employee and the company's people", %{catalog: catalog} do
    rows =
      walk(
        catalog,
        "users",
        ~w(name company.name company.parent.name employee.full_name
        company.users:count company.employees:count company.departments:count employee.subordinates:count),
        [91, 92, 93, 94, 95]
      )

    # Tenant 42's user and the unaffiliated user are outside the tenant's
    # list, so asking for them by key reaches nothing.
    assert rows |> Map.keys() |> Enum.sort() == [91, 92, 95]

    ada = rows[91]
    assert ada["company-name"] == "Bilimbi Industries"
    assert ada["company-parent-name"] == nil
    assert ada["employee-full_name"] == nil
    assert ada["company-users_count"] == 2
    assert ada["company-employees_count"] == 2
    assert ada["company-departments_count"] == 1

    boss = rows[95]
    assert boss["employee-full_name"] == "Boss Person"
    assert boss["employee-subordinates_count"] == 1

    grace = rows[92]
    assert grace["company-name"] == "Bilimbi Retail"
    assert grace["company-parent-name"] == "Bilimbi Industries"
    assert grace["company-users_count"] == 1
    # Employees are bounded to the actor's own company, so another company's
    # employees roll up to nothing rather than to a number the actor may not see.
    assert grace["company-employees_count"] == 0
  end

  test "companies roll up their people, addresses and attachments", %{catalog: catalog} do
    rows =
      walk(
        catalog,
        "companies",
        ~w(name users.email:list employees.full_name:list addresses:count
        primary_address.locality primary_address.country.country children:count employees.status:list),
        [73, 74, 75]
      )

    # Company 75 belongs to the other tenant.
    assert rows |> Map.keys() |> Enum.sort() == [73, 74]

    hq = rows[73]
    assert hq["users-email_list"] == "ada@example.com, boss.login@example.com"
    assert hq["employees-full_name_list"] == "Boss Person, Report Person"
    assert hq["employees-status_list"] == "active, probation"
    assert hq["addresses_count"] == 2
    assert hq["primary_address-locality"] == "Kuala Lumpur"
    assert hq["primary_address-country-country"] == "Malaysia"
    assert hq["children_count"] == 1

    retail = rows[74]
    assert retail["addresses_count"] == 0
    assert retail["primary_address-locality"] == nil
  end

  test "employees reach their type, department, supervisor and logins", %{
    catalog: catalog,
    boss: boss,
    report: report
  } do
    rows =
      walk(
        catalog,
        "employees",
        ~w(full_name type.label type.is_system department.type_name
        supervisor.full_name users.email:list addresses.locality:list company.name),
        [boss.id, report.id]
      )

    boss_row = rows[boss.id]
    assert boss_row["type-label"] != nil
    assert boss_row["type-is_system"] == true
    assert boss_row["users-email_list"] == "boss.login@example.com"
    assert boss_row["addresses-locality_list"] == "Penang"
    assert boss_row["company-name"] == "Bilimbi Industries"

    report_row = rows[report.id]
    assert report_row["supervisor-full_name"] == "Boss Person"
    assert report_row["users-email_list"] == nil
  end

  test "a narrower account sees a narrower catalog and cannot walk past it" do
    UserFixtures.insert_user!(%{
      id: 96,
      company_id: 73,
      name: "Narrow",
      email: "narrow@example.com"
    })

    grant_capabilities!(~w(admin.company.list), user_id: 96)
    {:ok, tenant_scope} = Tenancy.scope(41)
    catalog = Grid.catalog(Authentication.sign_in(tenant_scope, 96, 73))

    assert tables(catalog, @tables) == ~w(companies departments legal_entity_types)
    {:ok, companies} = Grid.fetch_table(catalog, "companies")

    assert {:error, {"users:count", {:forbidden_table, "users"}}} =
             Grid.resolve(catalog, companies, ~w(users:count))

    assert {:error, {"addresses:count", {:forbidden_table, "addresses"}}} =
             Grid.resolve(catalog, companies, ~w(addresses:count))

    assert {:ok, _} = Grid.resolve(catalog, companies, ~w(departments:count parent.name))
  end
end
