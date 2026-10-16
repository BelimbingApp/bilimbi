defmodule Bilimbi.Core.EmployeeEmploymentOwnerTest do
  @moduledoc """
  The runtime employment-owner seam: with no owner registered Core calls
  nothing, and a registered owner hears every legacy HR write inside Core's
  transaction, after Core wrote, and can refuse it.
  """

  # The owner registration is node-wide `:persistent_term` state.
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Person

  import Bilimbi.Core.Employee.TestFixtures

  defmodule RecordingOwner do
    @moduledoc false
    @behaviour Bilimbi.Core.Employee.EmploymentOwner

    # Reports what the owner reads back, from inside Core's transaction.
    @impl true
    def legacy_employee_written(scope, employee_id) do
      {:ok, employees} = Employee.get_tenant_employees(scope, [employee_id])
      {:ok, identities} = Employee.person_identities(scope, [employee_id])

      send(
        :persistent_term.get({__MODULE__, :test}),
        {:written, employee_id, Repo.in_transaction?(), Map.get(employees, employee_id),
         Map.get(identities, employee_id)}
      )

      :persistent_term.get({__MODULE__, :reply}, :ok)
    end

    @impl true
    def name, do: "People"

    @impl true
    def employment_path(_scope, company_id, employee_id),
      do: "/people/#{company_id}/employees/#{employee_id}"
  end

  defmodule OtherOwner do
    @moduledoc false
    def legacy_employee_written(_scope, _employee_id), do: :ok
    def name, do: "Other"
  end

  setup do
    create_employee_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Company A", code: "a"})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    :persistent_term.put({RecordingOwner, :test}, self())

    on_exit(fn ->
      Employee.unregister_employment_owner(RecordingOwner)
      Employee.unregister_employment_owner(OtherOwner)
      :persistent_term.erase({RecordingOwner, :test})
      :persistent_term.erase({RecordingOwner, :reply})
    end)

    %{scope: scope}
  end

  test "with no owner registered, writes call nothing and behave as before", %{scope: scope} do
    assert Employee.employment_owner() == nil
    assert Employee.employment_ownership(scope, 73, 1) == nil

    {:ok, employee} = create(scope, "E-1")
    {:ok, _} = Employee.update_employee(scope, 73, employee.id, %{status: "inactive"})
    :ok = Employee.delete_employee(scope, 73, employee.id)

    refute_received {:written, _, _, _, _}
  end

  test "one owner at a time; unregistering another module leaves it registered" do
    assert {:error, :invalid_owner} = Employee.register_employment_owner(String)
    assert {:error, :invalid_owner} = Employee.register_employment_owner("People")
    assert :ok = Employee.register_employment_owner(RecordingOwner)
    assert :ok = Employee.register_employment_owner(RecordingOwner)
    assert {:error, :already_registered} = Employee.register_employment_owner(OtherOwner)

    assert :ok = Employee.unregister_employment_owner(OtherOwner)
    assert Employee.employment_owner() == RecordingOwner

    assert :ok = Employee.unregister_employment_owner(RecordingOwner)
    assert Employee.employment_owner() == nil
  end

  test "the owner names itself and its page for an employee", %{scope: scope} do
    :ok = Employee.register_employment_owner(RecordingOwner)

    assert Employee.employment_ownership(scope, 73, 5) == %{
             name: "People",
             path: "/people/73/employees/5"
           }

    assert Employee.employment_ownership(scope, nil, nil) == %{name: "People", path: nil}

    :ok = Employee.unregister_employment_owner(RecordingOwner)
    :ok = Employee.register_employment_owner(OtherOwner)
    assert Employee.employment_ownership(scope, 73, 5) == %{name: "Other", path: nil}
  end

  test "create, update, subordinate assignment and delete each reach the owner after Core wrote",
       %{scope: scope} do
    :ok = Employee.register_employment_owner(RecordingOwner)

    {:ok, employee} = create(scope, "E-1")
    id = employee.id

    assert_received {:written, ^id, true, %{employee_number: "E-1", status: "active"},
                     %{person_id: person_id, company_id: 73}}

    assert is_integer(person_id)

    {:ok, _} =
      Employee.update_employee(scope, 73, id, %{
        status: "probation",
        employee_type: "contractor",
        employment_end: "2027-01-31",
        metadata: %{"grade" => "B"}
      })

    assert_received {:written, ^id, true,
                     %{
                       status: "probation",
                       employee_type: "contractor",
                       employment_end: ~D[2027-01-31],
                       metadata: %{"grade" => "B"}
                     }, %{person_id: ^person_id}}

    {:ok, supervisor} = create(scope, "E-2")
    supervisor_id = supervisor.id
    assert_received {:written, ^supervisor_id, true, _, _}

    {:ok, _} = Employee.assign_subordinate(scope, 73, supervisor_id, id)
    assert_received {:written, ^id, true, %{supervisor_id: ^supervisor_id}, _}

    {:ok, _} = Employee.remove_subordinate(scope, 73, supervisor_id, id)
    assert_received {:written, ^id, true, %{supervisor_id: nil}, _}

    # A deleted row is absent from the owner's read, and so is its mapping.
    :ok = Employee.delete_employee(scope, 73, id)
    assert_received {:written, ^id, true, nil, nil}
  end

  test "provisioning the platform orchestrator reaches the owner" do
    CompanyFixtures.assign_primary_company!(41, 73)
    :ok = Employee.register_employment_owner(RecordingOwner)

    assert {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    id = orchestrator.id

    assert_received {:written, ^id, true, %{employee_number: "SYS-001", employee_type: "agent"},
                     %{company_id: 73}}

    assert {:ok, _, :existing} = Employee.ensure_platform_orchestrator()
    refute_received {:written, _, _, _, _}
  end

  test "an owner refusal rolls the whole write back and reaches the caller", %{scope: scope} do
    {:ok, employee} = create(scope, "E-1")
    :ok = Employee.register_employment_owner(RecordingOwner)
    :persistent_term.put({RecordingOwner, :reply}, {:error, :employment_owner_refused})

    assert {:error, :employment_owner_refused} = create(scope, "E-2")
    assert {:ok, [_only]} = Employee.list_employees(scope, 73)
    assert {:ok, %{entries: [_only_person]}} = Person.list(scope)

    assert {:error, :employment_owner_refused} =
             Employee.update_employee(scope, 73, employee.id, %{status: "terminated"})

    assert {:ok, %{status: "active"}} = Employee.get_employee(scope, 73, employee.id)

    assert {:error, :employment_owner_refused} = Employee.delete_employee(scope, 73, employee.id)
    assert {:ok, _} = Employee.get_employee(scope, 73, employee.id)
  end

  defp create(scope, number),
    do:
      Employee.create_employee(scope, 73, %{employee_number: number, full_name: "Ann #{number}"})
end
