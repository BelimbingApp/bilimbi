defmodule Bilimbi.Core.Compatibility.PlatformBaselineSmoke do
  @moduledoc false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User

  @password "end-to-end-password"

  def run do
    {:ok, %{tenant: tenant, company: company}} =
      Company.provision_tenant(
        %{name: "End-to-end tenant"},
        %{name: "End-to-end company", code: "end_to_end_company"}
      )

    {:ok, scope} = Tenancy.scope(tenant.id)
    :ok = Employee.ensure_system_types()

    {:ok, employee} =
      Employee.create_employee(scope, company.id, %{
        employee_number: "E2E-001",
        full_name: "End-to-end employee"
      })

    {:ok, user} =
      User.create_user(scope, company.id, %{
        name: "End-to-end user",
        email: "e2e@example.test",
        employee_id: employee.id,
        password: @password
      })

    true = user.company_id == company.id
    true = user.employee_id == employee.id
    {:ok, [^user]} = User.list_users(scope)
    {:ok, ^user} = User.authenticate("e2e@example.test", @password)

    IO.puts("Platform baseline public API smoke passed.")
  end
end
