# Module-owned development sample data — core/company (#660).
#
# Discovered through the `dev_seed` descriptor key and run by `mix bilimbi.dev.seed`
# in dependency order, with `scope` and `company_id` bound. Idempotent and
# dev-only; references only the core/company public API.
#
# Both departments are seeded HEADLESS. A head is an employee, which core/company
# cannot name across the module boundary, so core/employee's seed — which runs
# after this one in dependency order — appoints a head on one of them through
# `Company.update_department_head/4`.
alias Bilimbi.Core.Company

{:ok, existing_types} = Company.list_department_types()

ensure_type = fn code, name ->
  case Enum.find(existing_types, &(&1.code == code)) do
    nil ->
      {:ok, type} = Company.create_department_type(%{code: code, name: name})
      type

    type ->
      type
  end
end

{:ok, existing_departments} = Company.list_departments(scope, company_id)

ensure_department = fn type_id ->
  case Enum.find(existing_departments, &(&1.department_type_id == type_id)) do
    nil ->
      {:ok, _dept} =
        Company.create_department(scope, company_id, %{
          department_type_id: type_id,
          status: "active"
        })

    _dept ->
      :ok
  end
end

engineering = ensure_type.("ENG", "Engineering")
operations = ensure_type.("OPS", "Operations")

ensure_department.(engineering.id)
ensure_department.(operations.id)
