defmodule Bilimbi.Core.CompanyAuthzHotPathTest do
  @moduledoc """
  Statement counts for one allowed `Authz.can/2` and `effective_capabilities/1`
  against the real company directory. The speed review measured 5 and 3.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company.AuthzCompanyDirectory

  import Bilimbi.Core.Company.TestFixtures

  @capability "admin.company.view"
  @user_id 91
  @home_company_id 73
  @sibling_company_id 74
  @deleted_company_id 76

  setup do
    Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    install_company_authz!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!()
    insert_company!()
    insert_company!(%{id: @sibling_company_id, code: "sibling", name: "Sibling"})

    insert_company!(%{
      id: @deleted_company_id,
      code: "deleted",
      name: "Deleted",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    {:ok, system_scope} = Tenancy.scope(41)
    scope = Authentication.sign_in(system_scope, @user_id, @home_company_id)
    {:ok, actor} = Authz.scope_actor(scope)

    %{scope: scope, system_scope: system_scope, actor: actor}
  end

  test "an allowed check reads the company once and skips the full company list", %{
    actor: actor
  } do
    grant!(@capability)

    can_queries =
      capture_queries(fn ->
        assert Authz.can(actor, @capability).allowed
      end)

    effective_queries =
      capture_queries(fn ->
        assert @capability in Authz.effective_capabilities(actor).allowed
      end)

    assert length(can_queries) == 3
    assert length(effective_queries) == 2

    assert Enum.any?(
             can_queries,
             &String.contains?(&1, "INSERT INTO \"base_authz_decision_logs\"")
           )

    refute Enum.any?(effective_queries, &String.contains?(&1, "INSERT INTO"))
    refute Enum.any?(can_queries ++ effective_queries, &String.contains?(&1, "legal_name"))
  end

  test "company_ids selects live ids only", %{scope: scope} do
    queries =
      capture_queries(fn ->
        assert AuthzCompanyDirectory.company_ids(scope) == [
                 @home_company_id,
                 @sibling_company_id
               ]
      end)

    assert [query] = queries
    assert query =~ ~s(SELECT c0."id" FROM "companies")
    assert query =~ "deleted_at"
    refute query =~ "legal_name"
  end

  test "a role owned by a sibling company still grants", %{scope: scope, actor: actor} do
    assert {:ok, role} =
             Authz.create_role(scope, @sibling_company_id, %{
               name: "Sibling",
               code: "sibling_role"
             })

    assert {:ok, 1} = Authz.replace_role_capabilities(scope, role.id, [@capability])
    assert {:ok, :assigned} = Authz.assign_role(scope, @home_company_id, :user, @user_id, role.id)

    assert Authz.can(actor, @capability).allowed
    assert @capability in Authz.effective_capabilities(actor).allowed
    assert Repo.get!(Role, role.id).company_id == @sibling_company_id
    assert Repo.get_by!(PrincipalRole, role_id: role.id).company_id == @home_company_id
  end

  test "a role owned by an archived company does not grant", %{actor: actor} do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, [%{id: role_id}]} =
      Repo.insert_all(
        Role,
        [
          %{
            company_id: @deleted_company_id,
            name: "Archived",
            code: "archived_role",
            is_system: false,
            grant_all: false,
            created_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    {1, _} =
      Repo.insert_all(RoleCapability, [
        %{
          role_id: role_id,
          capability_key: @capability,
          created_at: now,
          updated_at: now
        }
      ])

    {1, _} =
      Repo.insert_all(PrincipalRole, [
        %{
          company_id: @home_company_id,
          principal_type: "user",
          principal_id: @user_id,
          role_id: role_id,
          created_at: now,
          updated_at: now
        }
      ])

    decision = Authz.can(actor, @capability)
    refute decision.allowed
    refute @capability in Authz.effective_capabilities(actor).allowed
  end

  test "an archived actor company is an invalid context, before an unknown capability", %{
    system_scope: system_scope
  } do
    scope = Authentication.sign_in(system_scope, @user_id, @deleted_company_id)
    {:ok, actor} = Authz.scope_actor(scope)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(PrincipalCapability, [
      %{
        company_id: @deleted_company_id,
        principal_type: "user",
        principal_id: @user_id,
        capability_key: @capability,
        is_allowed: true,
        created_at: now,
        updated_at: now
      }
    ])

    assert Authz.can(actor, @capability).reason == :denied_invalid_actor_context
    assert Authz.can(actor, "admin.company.missing").reason == :denied_invalid_actor_context
  end

  test "a live company still reports an unknown capability", %{actor: actor} do
    assert Authz.can(actor, "admin.company.missing").reason == :denied_unknown_capability
  end

  test "a system grant-all role still allows, including a global assignment", %{actor: actor} do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, [%{id: role_id}]} =
      Repo.insert_all(
        Role,
        [
          %{
            company_id: nil,
            name: "All",
            code: "all_access",
            is_system: true,
            grant_all: true,
            created_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    {1, _} =
      Repo.insert_all(PrincipalRole, [
        %{
          company_id: nil,
          principal_type: "user",
          principal_id: @user_id,
          role_id: role_id,
          created_at: now,
          updated_at: now
        }
      ])

    assert Authz.can(actor, @capability).allowed
    assert @capability in Authz.effective_capabilities(actor).allowed
  end

  defp grant!(capability, company_id \\ @home_company_id) do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, company_id, :user, @user_id, capability, true)
  end

  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view"],
            capabilities: [@capability],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz}, "company-authz-hot-path")
  end

  defp capture_queries(fun) do
    handler = "authz-hot-path-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _, _, metadata, _ -> send(parent, {:authz_hot_query, metadata.query}) end,
      nil
    )

    fun.()
    :telemetry.detach(handler)

    receive_queries([])
  end

  defp receive_queries(queries) do
    receive do
      {:authz_hot_query, query} -> receive_queries([query | queries])
    after
      20 -> Enum.reverse(queries)
    end
  end
end
