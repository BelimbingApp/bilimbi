defmodule Bilimbi.Core.UserAdministration.TestCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

  # Not Authz's double: these tests need a second tenant with a company of its
  # own (20) and a third company (12) for tenant 1, which Authz's tests assert
  # are absent.
  @impl true
  def company_ids(%Scope{} = scope) do
    case Scope.tenant_id(scope) do
      1 -> [10, 11, 12]
      2 -> [20]
      _tenant_id -> []
    end
  end

  @impl true
  def company_in_scope?(%Scope{} = scope, company_id), do: company_id in company_ids(scope)

  @impl true
  def company_writable(scope, company_id),
    do: if(company_in_scope?(scope, company_id), do: :ok, else: {:error, :company_not_found})

  # Derived from `company_ids/1` so the two answers cannot drift apart.
  @impl true
  def companies_in_scope(%Scope{} = scope) do
    scope
    |> company_ids()
    |> Enum.map(&%{id: &1, name: "Company #{100 - &1}"})
    |> Enum.sort_by(&String.downcase(&1.name))
  end
end

defmodule Bilimbi.Core.UserAdministration.TestAuthz do
  @moduledoc false

  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Core.UserAdministration.TestCompanyDirectory

  def install_registry! do
    AuthzFixtures.install_test_registry!(
      descriptor: %{id: "core/user_administration", otp_app: :bilimbi_core_user_administration},
      company_directory: TestCompanyDirectory,
      fingerprint: "user-administration-test"
    )
  end
end
