# Module-owned development sample data — core/employee (#660).
#
# Runs AFTER core/company's seed in dependency order (core/employee declares the
# core/company edge), with `scope` and `company_id` bound. Idempotent and
# dev-only. Creates sample employees, then appoints one as the head of an
# existing department through core/company's public head-setter — the
# right-direction call that lets the company show page render one headed
# department (a resolved name) alongside one headless (an em dash).
alias Bilimbi.Core.Company
alias Bilimbi.Core.Employee

type_code = "permanent"

{:ok, existing_types} = Employee.list_employee_types(scope, company_id)

unless Enum.any?(existing_types, &(&1.code == type_code)) do
  {:ok, _type} =
    Employee.create_employee_type(scope, company_id, %{code: type_code, label: "Permanent"})
end

{:ok, existing_employees} = Employee.list_employees(scope, company_id)

ensure_employee = fn number, name ->
  case Enum.find(existing_employees, &(&1.employee_number == number)) do
    nil ->
      {:ok, employee} =
        Employee.create_employee(scope, company_id, %{
          employee_number: number,
          full_name: name,
          employee_type: type_code,
          status: "active"
        })

      employee

    employee ->
      employee
  end
end

head = ensure_employee.("EMP-001", "Ada Lovelace")
ensure_employee.("EMP-002", "Grace Hopper")
ensure_employee.("EMP-003", "Alan Turing")

# Appoint the head of the first seeded department. core/company left every
# department headless because it cannot name an employee; this is the seam's
# whole point — the dependent module completes the reference upward.
case Company.list_departments(scope, company_id) do
  {:ok, [department | _]} ->
    {:ok, _} = Company.update_department_head(scope, company_id, department.id, head.id)

  {:ok, []} ->
    :ok
end
