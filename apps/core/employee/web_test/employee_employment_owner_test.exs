defmodule BilimbiWeb.EmployeeEmploymentOwnerTest do
  # The employment owner is registered in node-wide `:persistent_term`, so a
  # concurrent test's employee writes and pages would see it.
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Person

  defmodule PeopleOwner do
    @moduledoc false
    @behaviour Bilimbi.Core.Employee.EmploymentOwner

    @impl true
    def legacy_employee_written(scope, employee_id) do
      {:ok, employees} = Employee.get_tenant_employees(scope, [employee_id])
      send(:persistent_term.get({__MODULE__, :test}), {:written, Map.get(employees, employee_id)})
      :ok
    end

    @impl true
    def name, do: "People"

    @impl true
    def employment_path(_scope, _company_id, employee_id), do: "/people/employees/#{employee_id}"
  end

  setup do
    signed_in_identity!()
    Person.TestFixtures.create_person_tables!()
    :ok = Employee.ensure_system_types()
    {:ok, system} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(system, 73, %{employee_number: "EMP-001", full_name: "John Doe"})

    :persistent_term.put({PeopleOwner, :test}, self())

    on_exit(fn ->
      Employee.unregister_employment_owner(PeopleOwner)
      :persistent_term.erase({PeopleOwner, :test})
    end)

    %{system: system, scope: Authentication.sign_in(system, 91, 73), employee: employee}
  end

  test "the batch mapping and handoff read need the employee read, not contact view", %{
    scope: scope,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.list"])

    assert {:ok, %{} = identities} = Employee.person_identities(scope, [employee.id])
    assert %{person_id: _, affiliation_id: _, company_id: 73} = identities[employee.id]
    assert {:error, :forbidden} = Employee.person_identity(scope, employee.id)

    assert {:ok, %{entries: [%{employee_id: id, person_id: person_id}]}} =
             Employee.hr_handoff_page(scope, nil)

    assert {id, person_id} == {employee.id, identities[employee.id].person_id}
  end

  test "an actor without the employee read is refused both reads", %{
    scope: scope,
    employee: employee
  } do
    grant_capabilities!(["admin.person.view", "admin.employee.view"])

    assert {:error, :forbidden} = Employee.person_identities(scope, [employee.id])
    assert {:error, :forbidden} = Employee.hr_handoff_page(scope, nil)
  end

  test "with no owner the pages say nothing about one", %{conn: conn, employee: employee} do
    grant_capabilities!(["admin.employee.list", "admin.employee.view"])

    {:ok, show, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
    refute has_element?(show, "#employment-owner-note")
    refute has_element?(show, "#employment-owner-link")

    {:ok, index, _html} = conn |> log_in_as() |> live(~p"/employees")
    refute has_element?(index, "#employment-owner-note")
  end

  test "with an owner the pages name it, link to it, and an edit here reaches it", %{
    conn: conn,
    employee: employee
  } do
    grant_capabilities!(["admin.employee.list", "admin.employee.view", "admin.employee.update"])
    :ok = Employee.register_employment_owner(PeopleOwner)

    {:ok, show, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")
    assert has_element?(show, "#employment-owner-note", "People owns the employee number")

    assert has_element?(
             show,
             "#employment-owner-link[href='/people/employees/#{employee.id}']",
             "Open in People"
           )

    render_hook(show, "save_status", %{"status" => "inactive"})
    assert_received {:written, %{id: id, status: "inactive"}}
    assert id == employee.id

    {:ok, index, _html} = conn |> log_in_as() |> live(~p"/employees")
    assert has_element?(index, "#employment-owner-note", "People owns the employee number")
  end
end
