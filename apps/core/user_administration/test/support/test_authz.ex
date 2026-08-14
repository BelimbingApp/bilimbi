defmodule Bilimbi.Core.UserAdministration.TestCompanyDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.Authz.CompanyDirectory

  alias Bilimbi.Base.Tenancy.Scope

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
end

defmodule Bilimbi.Core.UserAdministration.TestAuthz do
  @moduledoc false

  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Core.UserAdministration.TestCompanyDirectory

  def install_registry! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{
            id: "core/user_administration",
            otp_app: :bilimbi_core_user_administration
          },
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view"],
            capabilities: ["admin.test.record.view"],
            roles: %{
              "all_access" => %{name: "All Access", grant_all: true},
              "viewer" => %{
                name: "Viewer",
                capabilities: ["admin.test.record.view"]
              }
            },
            company_directory: TestCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "user-administration-test",
      consumers: %{settings: [], authz: authz, menu: []}
    })
  end
end
