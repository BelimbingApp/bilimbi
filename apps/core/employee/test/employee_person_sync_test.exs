defmodule Bilimbi.Core.EmployeePersonSyncTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Person

  import Bilimbi.Base.Database.TestHelpers
  import Bilimbi.Core.Employee.TestFixtures

  setup do
    create_employee_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Company A",
      code: "company_a"
    })

    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant B", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Company B",
      code: "company_b"
    })

    :ok = Employee.ensure_system_types()
    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)
    %{owner: owner, other: other}
  end

  test "a new employee is found by Person.list and resolves through person_identity", %{
    owner: owner,
    other: other
  } do
    assert {:ok, employee} =
             Employee.create_employee(owner, 73, %{
               employee_number: "E-1",
               full_name: "Nora Newhire",
               designation: "Analyst",
               email: "nora@work.test",
               mobile_number: "+60111",
               employment_start: "2026-02-01"
             })

    assert {:ok, %{entries: [person]}} = Person.list(owner, search: "nora@work.test")
    assert {person.full_name, person.email, person.phone} == {"Nora Newhire", nil, nil}

    assert {:ok, %{person_id: person_id, affiliation_id: affiliation_id, company_id: 73}} =
             Employee.person_identity(owner, employee.id)

    assert person_id == person.id

    assert {:ok, %{affiliations: [a]}} = Person.get(owner, person.id)

    assert {a.id, a.title, a.email, a.phone, a.started_on, a.legacy_employee_id} ==
             {affiliation_id, "Analyst", "nora@work.test", "+60111", ~D[2026-02-01], employee.id}

    assert {:ok, %{entries: []}} = Person.list(other, search: "Nora")
  end

  test "an edit carries only the changed facts and leaves Contacts edits alone", %{owner: owner} do
    {:ok, employee} =
      Employee.create_employee(owner, 73, %{
        employee_number: "E-2",
        full_name: "Omar Original",
        designation: "Clerk",
        email: "omar@work.test"
      })

    {:ok, %{person_id: person_id, affiliation_id: affiliation_id}} =
      Employee.person_identity(owner, employee.id)

    assert {:ok, _} =
             Person.update_affiliation(owner, person_id, affiliation_id, %{phone: "555-1"})

    assert {:ok, _} =
             Employee.update_employee(owner, 73, employee.id, %{
               designation: "Senior Clerk",
               full_name: "Omar Renamed",
               employment_end: "2027-01-31"
             })

    assert {:ok, %{full_name: "Omar Renamed", affiliations: [a]}} = Person.get(owner, person_id)

    assert {a.title, a.email, a.phone, a.ended_on} ==
             {"Senior Clerk", "omar@work.test", "555-1", ~D[2027-01-31]}

    assert {:ok, _} = Employee.update_employee(owner, 73, employee.id, %{status: "inactive"})
    assert {:ok, %{affiliations: [^a]}} = Person.get(owner, person_id)
  end

  test "a refused employee write leaves no person behind", %{owner: owner} do
    assert {:error, %Ecto.Changeset{} = changeset} =
             Employee.create_employee(owner, 73, %{full_name: "No Number"})

    assert %{employee_number: [_ | _]} = errors_on(changeset)
    assert {:ok, %{entries: [], total: 0}} = Person.list(owner)
  end

  test "the platform orchestrator is mapped like any other employee" do
    CompanyFixtures.assign_primary_company!(41, 73)
    assert {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    {:ok, owner} = Tenancy.scope(41)
    assert {:ok, %{company_id: 73}} = Employee.person_identity(owner, orchestrator.id)
  end

  test "deleting an employee ends its mapped affiliation and keeps the person", %{owner: owner} do
    {:ok, employee} =
      Employee.create_employee(owner, 73, %{
        employee_number: "E-3",
        full_name: "Dara Deleted",
        email: "dara@work.test"
      })

    {:ok, %{person_id: person_id, affiliation_id: affiliation_id}} =
      Employee.person_identity(owner, employee.id)

    assert :ok = Employee.delete_employee(owner, 73, employee.id)
    today = Date.utc_today()

    assert {:ok, %{full_name: "Dara Deleted", affiliations: [a]}} = Person.get(owner, person_id)
    assert {a.id, a.ended_on, a.legacy_employee_id} == {affiliation_id, today, employee.id}
    assert %NaiveDateTime{} = a.unlinked_at
    assert {:ok, contacts} = Person.work_contacts(owner, [person_id])
    assert contacts == %{}
    assert {:error, :employee_not_found} = Employee.person_identity(owner, employee.id)
  end

  test "an employee date that would invert the affiliation's range is refused", %{owner: owner} do
    {:ok, employee} =
      Employee.create_employee(owner, 73, %{
        employee_number: "E-4",
        full_name: "Ivy Inverted",
        employment_start: "2026-02-01"
      })

    {:ok, %{person_id: person_id, affiliation_id: affiliation_id}} =
      Employee.person_identity(owner, employee.id)

    assert {:ok, _} =
             Person.update_affiliation(owner, person_id, affiliation_id, %{
               started_on: "2026-06-01"
             })

    assert {:error, %Ecto.Changeset{} = changeset} =
             Employee.update_employee(owner, 73, employee.id, %{employment_end: "2026-03-31"})

    assert %{employment_end: [message]} = errors_on(changeset)
    assert message =~ "Contacts affiliation"
    assert {:ok, %{employment_end: nil}} = Employee.get_employee(owner, 73, employee.id)

    assert {:ok, %{affiliations: [%{started_on: ~D[2026-06-01], ended_on: nil}]}} =
             Person.get(owner, person_id)

    assert {:ok, _} =
             Employee.update_employee(owner, 73, employee.id, %{employment_end: "2026-12-31"})
  end

  test "an edit of an employee with no mapping creates one from the complete stored facts", %{
    owner: owner
  } do
    %{rows: [[id]]} =
      Ecto.Adapters.SQL.query!(
        Bilimbi.Base.Repo,
        """
        INSERT INTO employees (company_id, employee_number, full_name, designation, email,
                               mobile_number, employment_start, employment_end)
        VALUES (73, 'E-5', 'Una Unmapped', 'Clerk', 'una@work.test', '+60555', '2025-01-01', '2026-12-31')
        RETURNING id
        """,
        []
      )

    assert {:error, :not_found} = Bilimbi.Core.Person.legacy_affiliation(owner, id)

    assert {:ok, _} = Employee.update_employee(owner, 73, id, %{designation: "Senior Clerk"})

    assert {:ok, %{person_id: person_id}} = Employee.person_identity(owner, id)
    assert {:ok, %{full_name: "Una Unmapped", affiliations: [a]}} = Person.get(owner, person_id)

    assert {a.title, a.email, a.phone, a.started_on, a.ended_on, a.company_id} ==
             {"Senior Clerk", "una@work.test", "+60555", ~D[2025-01-01], ~D[2026-12-31], 73}

    assert {:ok, _} = Employee.update_employee(owner, 73, id, %{status: "inactive"})
    assert {:ok, %{affiliations: [^a]}} = Person.get(owner, person_id)
  end
end
