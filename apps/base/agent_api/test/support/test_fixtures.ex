defmodule Bilimbi.Base.AgentApi.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.AgentApi.ContributionValidator
  alias Bilimbi.Base.AgentApi.TestCompanyDirectory
  alias Bilimbi.Base.AgentApi.TestOperations
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  @descriptor %{id: "base/agent_api", otp_app: :bilimbi_base_agent_api}

  def descriptor, do: @descriptor

  @doc """
  Installs the test domain's capabilities and, unless `agent_api: nil` is
  given, its operations, over the registry's empty snapshot.
  """
  def install_test_registry!(opts \\ []) do
    authz =
      Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: @descriptor,
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "list", "update"],
            capabilities: TestOperations.capabilities(),
            roles: %{},
            company_directory: TestCompanyDirectory
          }
        }
      ])

    consumers =
      case Keyword.get(opts, :agent_api, TestOperations.payload()) do
        nil ->
          %{authz: authz}

        payload ->
          %{
            authz: authz,
            agent_api:
              ContributionValidator.validate_contributions!([
                %{descriptor: @descriptor, payload: payload}
              ])
          }
      end

    ContributionRegistry.put_consumers_for_test!(consumers, "agent-api-test")
  end

  @doc "A system scope for a tenant, with no tenants table behind it."
  def system_scope(tenant_id) do
    Scope.for_tenant(%Identity{
      id: tenant_id,
      name: "Tenant #{tenant_id}",
      status: "active",
      is_platform_operator: false
    })
  end

  @doc "A tenant-1 person (user 7, company 10) signed in with these capabilities granted."
  def user_scope(capabilities) when is_list(capabilities) do
    system = system_scope(1)

    for capability <- capabilities do
      {:ok, :stored} = Authz.put_principal_capability(system, 10, :user, 7, capability, true)
    end

    Authentication.sign_in(system, 7, 10)
  end
end
