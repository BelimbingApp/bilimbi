defmodule Bilimbi.Base.Authz.CompanyGrantTest do
  @moduledoc """
  A user signed in at one company may hold a grant in another company of the
  same tenant. `can_in_company/5` judges that grant for the scope's own user,
  and only in a live company of the scope's tenant.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication

  import Bilimbi.Base.Authz.TestFixtures

  @capability "admin.test.record.view"

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    # User 7 signs in at company 10 and holds the capability only in company 11.
    assert {:ok, :stored} =
             Authz.put_principal_capability(scope(), 11, :user, 7, @capability, true)

    %{admin: Authentication.sign_in(scope(), 7, 10)}
  end

  test "a grant in another company of the tenant decides there, not at sign-in", %{admin: admin} do
    resource = Authz.resource("record", 1, scope: scope(), company_id: 11)

    assert Authz.can(admin, @capability, resource).reason == :denied_company_scope
    refute Authz.can(admin, @capability).allowed

    assert Authz.can_in_company(admin, 11, @capability, resource).allowed
    assert Authz.can_in_company(admin, 11, @capability).allowed
  end

  test "the decision is logged against the named company and keeps the sign-in company", %{
    admin: admin
  } do
    assert Authz.can_in_company(admin, 11, @capability, nil, %{signed_in_company_id: 99}).allowed

    assert [log] = Repo.all(DecisionLog)
    assert %{actor_type: "user", actor_id: 7, company_id: 11, allowed: true} = log
    assert log.context == %{"signed_in_company_id" => 10}
  end

  test "the sign-in company is judged exactly as can/4 judges it", %{admin: admin} do
    decision = Authz.can_in_company(admin, 10, @capability)

    assert decision == Authz.can(admin, @capability)
    assert decision.reason == :denied_missing_capability
  end

  test "another user gains nothing from the grant", %{admin: _admin} do
    other = Authentication.sign_in(scope(), 9, 10)

    assert Authz.can_in_company(other, 11, @capability).reason == :denied_missing_capability
  end

  test "a resource in a different company than the one named is refused", %{admin: admin} do
    resource = Authz.resource("record", 1, company_id: 10)

    assert Authz.can_in_company(admin, 11, @capability, resource).reason == :denied_company_scope
  end

  test "a resource of another tenant is refused", %{admin: admin} do
    resource = Authz.resource("record", 1, scope: scope(2), company_id: 11)

    assert Authz.can_in_company(admin, 11, @capability, resource).reason == :denied_tenant_scope
  end

  test "a company that is not live in the scope's tenant is refused whatever is stored", %{
    admin: admin
  } do
    # Company 12 is not a live company of tenant 1: archived, missing, or
    # another tenant's all look the same to the directory. Neither a grant
    # row naming it nor a company-less grant opens it.
    Repo.insert_all(PrincipalCapability, [
      %{company_id: 12, principal_type: "user", principal_id: 7, capability_key: @capability},
      %{company_id: nil, principal_type: "user", principal_id: 7, capability_key: @capability}
    ])

    decision = Authz.can_in_company(admin, 12, @capability)

    refute decision.allowed
    assert decision.reason == :denied_company_scope
    assert [%{company_id: 12, allowed: false}] = Repo.all(DecisionLog)
  end

  test "a user of another tenant cannot reach this tenant's company", %{admin: _admin} do
    Repo.insert_all(PrincipalCapability, [
      %{company_id: 11, principal_type: "user", principal_id: 8, capability_key: @capability}
    ])

    outsider = Authentication.sign_in(scope(2), 8, 20)

    assert Authz.can_in_company(outsider, 11, @capability).reason == :denied_company_scope
  end

  test "an anonymous system scope names nobody and is denied", %{admin: _admin} do
    decision = Authz.can_in_company(scope(), 11, @capability)

    assert decision.reason == :denied_no_authenticated_actor
    assert Repo.all(DecisionLog) == []
  end
end
