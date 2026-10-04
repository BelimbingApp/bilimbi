defmodule Bilimbi.Core.CompanySelectableCompaniesTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company

  import Bilimbi.Core.Company.TestFixtures

  @operation "admin.company.view"
  @reach "admin.company.tenant-wide.manage"
  @user_id 91
  @home_company_id 73
  @sibling_company_id 74
  @foreign_company_id 75
  @deleted_company_id 76

  setup do
    Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    install_company_authz!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!()
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    insert_company!()
    insert_company!(%{id: @sibling_company_id, code: "sibling", name: "Sibling"})
    insert_company!(%{id: @foreign_company_id, tenant_id: 42, code: "foreign", name: "Foreign"})

    insert_company!(%{
      id: @deleted_company_id,
      code: "deleted",
      name: "Deleted",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    {:ok, system_scope} = Tenancy.scope(41)
    scope = Authentication.sign_in(system_scope, @user_id, @home_company_id)

    %{system_scope: system_scope, scope: scope}
  end

  test "scope and actor clauses agree on the actor's own company", %{scope: scope} do
    grant!(@operation)

    assert_clauses_agree(scope, @operation, target_ids())

    assert {:ok, companies} = Company.list_selectable_companies(scope, @operation)
    assert Enum.map(companies, & &1.id) == [@home_company_id]

    assert {:ok, %{id: @home_company_id}} =
             Company.authorize_company_target(scope, @home_company_id, @operation)

    assert {:error, :unauthorized} =
             Company.authorize_company_target(scope, @sibling_company_id, @operation)
  end

  test "scope and actor clauses agree when tenant-wide reach includes siblings", %{scope: scope} do
    grant!(@operation)
    grant!(@reach)

    assert_clauses_agree(scope, @operation, target_ids())

    assert {:ok, companies} = Company.list_selectable_companies(scope, @operation)
    assert Enum.map(companies, & &1.id) == [@home_company_id, @sibling_company_id]

    assert {:ok, %{id: @sibling_company_id}} =
             Company.authorize_company_target(scope, @sibling_company_id, @operation)

    assert {:error, :not_found} =
             Company.authorize_company_target(scope, @foreign_company_id, @operation)

    assert {:error, :not_found} =
             Company.authorize_company_target(scope, @deleted_company_id, @operation)
  end

  test "reach alone does not authorize the operation for either clause", %{scope: scope} do
    grant!(@reach)

    assert_clauses_agree(scope, @operation, target_ids())

    assert {:error, :unauthorized} = Company.list_selectable_companies(scope, @operation)

    assert {:error, :unauthorized} =
             Company.authorize_company_target(scope, @home_company_id, @operation)
  end

  test "a signed-in actor is limited to the company on the scope", %{system_scope: system_scope} do
    grant!(@operation, @sibling_company_id)
    scope = Authentication.sign_in(system_scope, @user_id, @sibling_company_id)

    assert_clauses_agree(scope, @operation, target_ids())

    assert {:ok, companies} = Company.list_selectable_companies(scope, @operation)
    assert Enum.map(companies, & &1.id) == [@sibling_company_id]
  end

  test "a system scope names nobody", %{system_scope: system_scope} do
    grant!(@operation)
    grant!(@reach)

    assert {:error, :unauthorized} = Company.list_selectable_companies(system_scope, @operation)

    assert {:error, :unauthorized} =
             Company.authorize_company_target(system_scope, @home_company_id, @operation)

    assert {:error, :not_found} = Company.authorize_company_target(system_scope, 0, @operation)
    assert {:error, :not_found} = Company.authorize_company_target(system_scope, -1, @operation)
    assert {:error, :not_found} = Company.authorize_company_target(system_scope, "73", @operation)
  end

  defp assert_clauses_agree(scope, capability, company_ids) do
    {:ok, actor} = Authz.scope_actor(scope)

    assert Company.list_selectable_companies(scope, capability) ==
             Company.list_selectable_companies(actor, capability)

    Enum.each(company_ids, fn company_id ->
      assert Company.authorize_company_target(scope, company_id, capability) ==
               Company.authorize_company_target(actor, company_id, capability)
    end)
  end

  defp target_ids do
    [@home_company_id, @sibling_company_id, @foreign_company_id, @deleted_company_id, 0, -1, "73"]
  end

  defp grant!(capability, company_id \\ @home_company_id) do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               scope,
               company_id,
               :user,
               @user_id,
               capability,
               true
             )
  end

  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "manage"],
            capabilities: [@operation, @reach],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz}, "company-selectable")
  end
end
