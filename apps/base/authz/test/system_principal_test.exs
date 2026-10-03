defmodule Bilimbi.Base.Authz.SystemPrincipalTest do
  @moduledoc """
  A named system principal holds exactly what an administrator granted it,
  per company, among the capabilities its module declared. Nothing is
  granted by default, revocation takes effect at the next decision, another
  tenant's grant is never visible, and every grant and revocation records who
  made it.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.SystemPrincipalCapability
  alias Bilimbi.Base.Authz.SystemPrincipalGrant
  alias Bilimbi.Base.Authz.TestCompanyDirectory
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.SystemPrincipals.ContributionValidator, as: PrincipalValidator

  import Bilimbi.Base.Authz.TestFixtures, only: [create_authz_tables!: 0]
  import Bilimbi.Base.Tenancy.TestFixtures

  @principal "coating.line_import"
  @import "factory.material.import"
  @view "factory.item.view"
  @platform "admin.test.platform.manage"
  @undeclared "admin.test.record.view"
  @grant "admin.authz.system-principal.grant"
  @revoke "admin.authz.system-principal.revoke"
  @list "admin.authz.system-principal.list"

  setup do
    create_authz_tables!()
    AuditFixtures.create_audit_tables!()
    create_tenants_table!()
    insert_tenant!(%{id: 1, is_platform_operator: false})
    insert_tenant!(%{id: 2, name: "Other", is_platform_operator: false})
    {:ok, tenant} = Tenancy.scope(1)
    {:ok, other_tenant} = Tenancy.scope(2)

    install_registry!(declared: [@import, @view, @platform])
    on_exit(&ContributionRegistry.clear_for_test!/0)
    on_exit(fn -> AuditContext.put(nil) end)

    admin = Authentication.sign_in(tenant, 7, 10)

    for capability <- [@grant, @revoke, @list] do
      assert {:ok, :stored} =
               Authz.put_principal_capability(tenant, 10, :user, 7, capability, true)
    end

    %{tenant: tenant, other_tenant: other_tenant, admin: admin}
  end

  describe "a principal's decisions" do
    test "nothing is granted by default", %{tenant: tenant} do
      decision = Authz.can(principal(tenant, 10), @import)

      refute decision.allowed
      assert decision.reason == :denied_missing_capability
    end

    test "a named principal cannot use a platform capability in an ordinary tenant", %{
      tenant: tenant,
      admin: admin
    } do
      assert {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @platform)

      decision = Authz.can(principal(tenant, 10), @platform)

      refute decision.allowed
      assert decision.reason == :denied_platform_scope
    end

    test "a granted capability allows in that company, and the log names the principal", %{
      tenant: tenant,
      admin: admin
    } do
      assert {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      Repo.delete_all(DecisionLog)

      job = principal(tenant, 10)
      decision = Authz.can(job, @import)

      assert decision.allowed
      assert "system_principal_grant" in decision.policies
      assert :ok = Authz.authorize!(job, @import)

      assert [%DecisionLog{} = log | _rest] = Repo.all(DecisionLog)
      assert %{actor_type: "system", actor_id: 0, company_id: 10, allowed: true} = log
      assert log.context["system_principal"] == @principal

      assert %{entries: [summary | _rest]} = Authz.list_decision_logs(tenant)
      assert %{actor_type: "system", actor_id: 0, system_principal: @principal} = summary
    end

    test "a caller's context cannot rename the principal in the log", %{
      tenant: tenant,
      admin: admin
    } do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      Repo.delete_all(DecisionLog)

      Authz.can(principal(tenant, 10), @import, nil, %{system_principal: "someone.else"})

      assert [log] = Repo.all(DecisionLog)
      assert log.context == %{"system_principal" => @principal}
    end

    test "a grant is for one capability in one company", %{tenant: tenant, admin: admin} do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)

      refute Authz.can(principal(tenant, 10), @view).allowed
      refute Authz.can(principal(tenant, 11), @import).allowed

      resource = Authz.resource("factory.order", 5, company_id: 11)
      decision = Authz.can(principal(tenant, 10), @import, resource)
      assert decision.reason == :denied_company_scope
    end

    test "revocation denies at the next decision", %{tenant: tenant, admin: admin} do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      job = principal(tenant, 10)
      assert Authz.can(job, @import).allowed

      assert {:ok, :revoked} = Authz.revoke_system_capability(admin, 10, @principal, @import)
      assert {:ok, :not_found} = Authz.revoke_system_capability(admin, 10, @principal, @import)

      decision = Authz.can(job, @import)
      refute decision.allowed
      assert decision.reason == :denied_missing_capability
    end

    test "is never a user who could approve", %{tenant: tenant, admin: admin} do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)

      assert {:error, :no_authenticated_actor} = Authz.scope_actor(principal(tenant, 10))
    end

    test "only what its module declares: an undeclared capability cannot be granted or held", %{
      tenant: tenant,
      admin: admin
    } do
      assert {:error, :capability_not_declared} =
               Authz.grant_system_capability(admin, 10, @principal, @undeclared)

      assert {:error, {:unknown_capabilities, ["factory.unknown.view"]}} =
               Authz.grant_system_capability(admin, 10, @principal, "factory.unknown.view")

      # A row written around the API grants nothing it was not declared for.
      insert_raw_grant!(10, @principal, @undeclared)
      refute Authz.can(principal(tenant, 10), @undeclared).allowed

      # A capability the module stops declaring stops being held.
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @view)
      assert Authz.can(principal(tenant, 10), @view).allowed

      install_registry!(declared: [@import])
      refute Authz.can(principal(tenant, 10), @view).allowed
    end

    test "a principal no installed module declares holds nothing", %{tenant: tenant, admin: admin} do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      job = principal(tenant, 10)

      install_registry!(declared: [@import], principals: [])

      decision = Authz.can(job, @import)
      refute decision.allowed
      assert decision.reason == :denied_invalid_actor_context

      assert {:error, :undeclared_system_principal} =
               Authz.grant_system_capability(admin, 10, @principal, @import)
    end
  end

  describe "tenant boundary" do
    test "a principal cannot act in another tenant's company", %{
      tenant: tenant,
      other_tenant: other_tenant,
      admin: admin
    } do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)

      # Tenant 2's job naming tenant 1's company is not in its scope.
      decision = Authz.can(principal(other_tenant, 10), @import)
      refute decision.allowed
      assert decision.reason == :denied_invalid_actor_context

      resource = Authz.resource("factory.order", 5, scope: other_tenant)
      assert Authz.can(principal(tenant, 10), @import, resource).reason == :denied_tenant_scope
    end

    test "another tenant's administrator can neither see nor change the grant", %{
      tenant: tenant,
      other_tenant: other_tenant,
      admin: admin
    } do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)

      # User 7 holds the administration grants in company 10, but a session
      # in tenant 2 cannot bring company 10 with it.
      other_admin = Authentication.sign_in(other_tenant, 7, 10)

      assert {:error, :forbidden} =
               Authz.grant_system_capability(other_admin, 10, @principal, @view)

      assert {:error, :forbidden} = Authz.list_system_capabilities(other_admin)

      # Through the operator's path, which skips the administrator check, the
      # company is still judged against the tenant.
      console = %{actor_type: "console", actor_id: 0}
      registry = ContributionRegistry.consumer!(:authz)

      assert {:error, :company_not_found} =
               Authz.SystemPrincipalService.grant(
                 other_tenant,
                 10,
                 @principal,
                 @view,
                 console,
                 registry
               )

      assert {:ok, :not_found} =
               Authz.SystemPrincipalService.revoke(
                 other_tenant,
                 10,
                 @principal,
                 @import,
                 console,
                 registry
               )

      assert [] = Authz.SystemPrincipalService.list(other_tenant, [], registry)
      assert Authz.can(principal(tenant, 10), @import).allowed
    end
  end

  describe "administration" do
    test "grants are listed for the scope's companies", %{admin: admin} do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      {:ok, :existing} = Authz.grant_system_capability(admin, 10, @principal, @import)
      {:ok, :granted} = Authz.grant_system_capability(admin, 11, @principal, @view)

      assert {:ok,
              [
                %SystemPrincipalGrant{company_id: 10, principal: @principal, capability: @import},
                %SystemPrincipalGrant{company_id: 11, principal: @principal, capability: @view}
              ]} = Authz.list_system_capabilities(admin)

      assert {:ok, []} = Authz.list_system_capabilities(admin, principal: "coating.other")

      assert [%{name: @principal, capabilities: [@view, @import]}] =
               Authz.list_system_principals()
    end

    test "is a person's act: a user without the capability or any system scope is refused", %{
      tenant: tenant,
      admin: admin
    } do
      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      bystander = Authentication.sign_in(tenant, 9, 10)
      job = principal(tenant, 10)

      for scope <- [bystander, tenant, job] do
        assert {:error, :forbidden} = Authz.grant_system_capability(scope, 10, @principal, @view)

        assert {:error, :forbidden} =
                 Authz.revoke_system_capability(scope, 10, @principal, @import)

        assert {:error, :forbidden} = Authz.list_system_capabilities(scope)
      end

      assert Repo.aggregate(SystemPrincipalCapability, :count) == 1
    end

    test "an unknown company is refused", %{admin: admin} do
      assert {:error, :company_not_found} =
               Authz.grant_system_capability(admin, 99, @principal, @import)
    end

    test "records who granted and who revoked, with the change", %{admin: admin} do
      AuditContext.put(%AuditContext{actor_type: "user", actor_id: 7, company_id: 10})

      {:ok, :granted} = Authz.grant_system_capability(admin, 10, @principal, @import)
      {:ok, :revoked} = Authz.revoke_system_capability(admin, 10, @principal, @import)

      assert [granted, revoked] = Repo.all(from(a in ActionSchema, order_by: a.id))

      assert %{
               event: "authz.system_principal.granted",
               actor_type: "user",
               actor_id: 7,
               company_id: 10,
               tenant_id: 1,
               system_principal: nil,
               is_retained: true
             } = granted

      assert granted.payload["context"] == %{
               "system_principal" => @principal,
               "company_id" => 10,
               "capability" => @import
             }

      assert %{event: "authz.system_principal.revoked", actor_type: "user", actor_id: 7} = revoked

      assert [
               %{event: "created", actor_type: "user", actor_id: 7},
               %{event: "deleted", actor_type: "user", actor_id: 7}
             ] = grant_mutations()
    end

    test "records the operator behind an impersonated administrator", %{tenant: tenant} do
      impersonated =
        Authentication.sign_in(tenant, 7, 10, impersonator_id: 3, impersonation_session_id: "s1")

      {:ok, :granted} = Authz.grant_system_capability(impersonated, 10, @principal, @import)

      assert [%{actor_id: 7, impersonator_id: 3}] = Repo.all(ActionSchema)
    end
  end

  describe "the operator's mix task" do
    test "grants and revokes as the console", %{tenant: tenant} do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      task = Mix.Tasks.Bilimbi.Authz.SystemPrincipal

      task.run(
        ~w(grant --tenant 1 --company 10 --principal #{@principal} --capability #{@import})
      )

      assert_received {:mix_shell, :info, ["Granted " <> _]}
      assert Authz.can(principal(tenant, 10), @import).allowed

      task.run(~w(grants --tenant 1))
      assert_received {:mix_shell, :info, ["coating.line_import company 10: " <> @import]}

      task.run(
        ~w(revoke --tenant 1 --company 10 --principal #{@principal} --capability #{@import})
      )

      assert_received {:mix_shell, :info, ["Revoked " <> _]}
      refute Authz.can(principal(tenant, 10), @import).allowed

      assert [%{actor_type: "console", actor_id: 0}, %{actor_type: "console", actor_id: 0}] =
               Repo.all(from(a in ActionSchema, order_by: a.id))

      assert [
               %{event: "created", actor_type: "console", actor_id: 0},
               %{event: "deleted", actor_type: "console", actor_id: 0}
             ] = grant_mutations()

      assert_raise Mix.Error, ~r/capability_not_declared/, fn ->
        task.run(
          ~w(grant --tenant 1 --company 10 --principal #{@principal} --capability #{@undeclared})
        )
      end

      assert_raise Mix.Error, ~r/--company is required/, fn ->
        task.run(~w(grant --tenant 1 --principal #{@principal} --capability #{@import}))
      end
    end
  end

  # A job's scope, built the one way Base Queue builds it when the job runs.
  defp principal(scope, company_id) do
    {:ok, token} = Authentication.delegate_system(scope, @principal, company_id)
    {:ok, job_scope} = Authentication.resume_system(token)
    job_scope
  end

  defp grant_mutations do
    Repo.all(
      from(m in MutationSchema,
        where: m.auditable_type == ^inspect(SystemPrincipalCapability),
        order_by: m.id
      )
    )
  end

  defp insert_raw_grant!(company_id, principal, capability) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(SystemPrincipalCapability, [
      %{
        company_id: company_id,
        principal: principal,
        capability_key: capability,
        created_at: now,
        updated_at: now
      }
    ])
  end

  defp install_registry!(opts) do
    declared = Keyword.fetch!(opts, :declared)
    principals = Keyword.get(opts, :principals, [@principal])

    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/authz", otp_app: :bilimbi_base_authz},
          payload: %{
            domains: %{"admin" => "Administrative operations", "factory" => "Factory"},
            verbs: ["view", "grant", "revoke", "list", "import", "manage"],
            capabilities: [@undeclared, @import, @view, @platform, @grant, @revoke, @list],
            platform_capabilities: [@platform],
            roles: %{},
            company_directory: TestCompanyDirectory
          }
        }
      ])

    system_principals =
      PrincipalValidator.validate_contributions!([
        %{
          descriptor: %{id: "ext/coating", otp_app: :bilimbi_base_authz},
          payload:
            Enum.map(principals, fn name ->
              %{
                name: name,
                description: "Imports coating line production records.",
                capabilities: declared
              }
            end)
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "authz-test",
      consumers:
        Map.merge(ContributionRegistry.build!([]).consumers, %{
          authz: authz,
          system_principals: system_principals
        })
    })
  end
end
