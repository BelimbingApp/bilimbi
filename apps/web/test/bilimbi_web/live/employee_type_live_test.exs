defmodule BilimbiWeb.EmployeeTypeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employee-types")
  end

  test "redirects away when the actor lacks admin.employee-type.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employee-types")
  end

  test "lists system types", %{conn: conn} do
    grant_capabilities!(["admin.employee.list", "admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    assert has_element?(view, "#nav-admin-employee-type[aria-current='page']")
    assert has_element?(view, "#employee-types td", "Full Time")
    assert has_element?(view, "#employee-types td", "Agent")
    refute has_element?(view, "#employee-type-new")
  end

  test "creates a custom type", %{conn: conn} do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/new")

    view
    |> form("#employee-type-form", employee_type: %{code: "seasonal", label: "Seasonal"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employee-types"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(index, "#employee-types td", "Seasonal")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, types} = Employee.list_employee_types(scope, 73)
    assert Enum.any?(types, &(&1.code == "seasonal" and not &1.is_system))
  end

  test "updates a custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp_contractor",
        label: "Temporary Contractor"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}/edit")

    view
    |> form("#employee-type-form", employee_type: %{label: "Independent Contractor"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employee-types"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(index, "#employee-types td", "Independent Contractor")

    assert {:ok, updated} = Employee.get_employee_type(scope, 73, type.id)
    assert updated.label == "Independent Contractor"
    assert updated.code == "temp_contractor"
  end

  test "forbids editing a system type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    assert {:error,
            {:live_redirect,
             %{
               to: "/employee-types",
               flash: %{"error" => "System employee types cannot be edited."}
             }}} =
             conn |> log_in_as() |> live(~p"/employee-types/#{system_type.id}/edit")
  end

  test "deletes a custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp",
        label: "Temporary"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")
    assert has_element?(view, "#employee-type-delete-#{type.id}")

    view
    |> element("#employee-type-delete-#{type.id}")
    |> render_click()

    refute has_element?(view, "#employee-types td", "Temporary")
    assert render(view) =~ "Employee type deleted."

    assert {:error, :type_not_found} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "rejects deleting an in-use custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "consultant",
        label: "Consultant"
      })

    {:ok, _employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-0099",
        full_name: "Grace Hopper",
        short_name: "Grace",
        designation: "Lead Consultant",
        employee_type: "consultant",
        email: "grace@navy.mil",
        status: "active"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    view
    |> element("#employee-type-delete-#{type.id}")
    |> render_click()

    assert render(view) =~ "Cannot delete: employees are using this type."
    assert {:ok, _} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "system types do not show edit or delete action links", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!([
      "admin.employee-type.list",
      "admin.employee-type.update",
      "admin.employee-type.delete"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    refute has_element?(view, "#employee-type-edit-#{system_type.id}")
    refute has_element?(view, "#employee-type-delete-#{system_type.id}")
  end
end
