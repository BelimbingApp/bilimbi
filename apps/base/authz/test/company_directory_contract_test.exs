defmodule Bilimbi.Base.Authz.CompanyDirectoryContractTest do
  @moduledoc """
  The two properties `companies_in_scope/1` promises, checked on a double.

  Base cannot reach Core, so the real directory is exercised in
  `apps/core/company/test/company_test.exs`. What this file protects is the
  contract *as written* — a callback whose docs promise an ordering and a
  matching id set, but whose only enforcement is the honesty of each
  implementor, is a promise callers will build a form on and discover is false
  at submit time.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.Authz.TestCompanyDirectory, as: Directory
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  setup do
    %{populated: scope_for(1), empty: scope_for(2)}
  end

  test "reports the same companies as company_ids/1", %{populated: scope} do
    named = Directory.companies_in_scope(scope)

    assert named |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort(Directory.company_ids(scope))

    # Every offered option must survive the check the form will run on submit.
    assert Enum.all?(named, &Directory.company_in_scope?(scope, &1.id))
  end

  test "orders by the name that gets displayed, not by id", %{populated: scope} do
    named = Directory.companies_in_scope(scope)

    assert named == Enum.sort_by(named, & &1.name)

    # The double names companies in descending id order precisely so this
    # assertion fails if someone "fixes" the sort to use id.
    refute named == Enum.sort_by(named, & &1.id)
  end

  test "an empty scope yields no companies, not an error", %{empty: scope} do
    assert Directory.companies_in_scope(scope) == []
  end

  # Built straight from an Identity rather than through `Tenancy.scope/1`, which
  # would need a tenant row and drag a DataCase into what is a pure test.
  defp scope_for(tenant_id) do
    Scope.for_tenant(%Identity{
      id: tenant_id,
      name: "Tenant #{tenant_id}",
      status: "active",
      is_platform_operator: false
    })
  end
end
