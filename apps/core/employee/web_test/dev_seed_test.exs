defmodule BilimbiWeb.DevSeedTest do
  @moduledoc """
  The module-owned dev-seed contributions (#660): discovered in dependency order
  and completing the department head across the core/company ← core/employee seam.

  It lives in web_test because `ModuleRegistry.dev_seed_paths!/0` resolves the
  whole installed graph, which only exists with every module loaded — the same
  context `mix bilimbi.dev.seed` runs in.
  """
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    # create_user_tables! chains into create_employee_tables!, which builds the
    # company, department, employee, and employee-type tables plus the head FK.
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_department_types_table!()
    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Bilimbi", code: "bilimbi"})

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope, company_id: 73}
  end

  # Evaluate each discovered dev-seed script exactly as `bilimbi.dev.seed` does.
  defp run_seeds(paths, scope, company_id) do
    Enum.each(paths, fn path ->
      Code.eval_string(File.read!(path), [scope: scope, company_id: company_id], file: path)
    end)
  end

  defp seed_paths, do: ModuleRegistry.dev_seed_paths!()

  test "core/company's seed sorts before core/employee's" do
    paths = seed_paths()
    company_idx = Enum.find_index(paths, &String.contains?(&1, "bilimbi_core_company"))
    employee_idx = Enum.find_index(paths, &String.contains?(&1, "bilimbi_core_employee"))

    assert is_integer(company_idx), "core/company must ship a dev seed"
    assert is_integer(employee_idx), "core/employee must ship a dev seed"
    assert company_idx < employee_idx, "the dependency must be seeded first"
  end

  test "seeding yields one headed department (a resolved name) and one headless", ctx do
    run_seeds(seed_paths(), ctx.scope, ctx.company_id)

    {:ok, departments} = Company.list_departments(ctx.scope, ctx.company_id)
    {:ok, employees} = Employee.list_employees(ctx.scope, ctx.company_id)

    assert length(departments) == 2
    assert length(employees) == 3

    heads = Enum.map(departments, & &1.head_id)
    assert Enum.count(heads, &is_nil/1) == 1
    assert Enum.count(heads, &(not is_nil(&1))) == 1

    headed = Enum.find(departments, & &1.head_id)
    {:ok, resolved} = Employee.get_tenant_employees(ctx.scope, [headed.head_id])
    assert resolved[headed.head_id].full_name == "Ada Lovelace"
  end

  test "the seeds are idempotent — a second run adds nothing", ctx do
    paths = seed_paths()
    run_seeds(paths, ctx.scope, ctx.company_id)
    run_seeds(paths, ctx.scope, ctx.company_id)

    {:ok, departments} = Company.list_departments(ctx.scope, ctx.company_id)
    {:ok, employees} = Employee.list_employees(ctx.scope, ctx.company_id)

    assert length(departments) == 2
    assert length(employees) == 3
  end
end
