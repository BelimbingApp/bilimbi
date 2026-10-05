defmodule Bilimbi.Base.Tenancy.SystemPrincipalTest do
  @moduledoc """
  A named system principal is a declared identity a job runs as. Only a name
  an installed module declares can be sealed onto a scope, only from a token
  Base Tenancy signed, and the actor stays a system actor: never a user,
  never signed in over, never impersonated.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.ForgedActorError
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals
  alias Bilimbi.Base.Tenancy.SystemPrincipals.ContributionValidator

  import Bilimbi.Base.Tenancy.TestFixtures

  @principal "coating.line_import"

  setup do
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    {:ok, operator} = Tenancy.scope(41)
    {:ok, customer} = Tenancy.scope(42)

    install_principals!([declaration(@principal)])
    on_exit(&ContributionRegistry.clear_for_test!/0)

    %{operator: operator, customer: customer}
  end

  describe "declarations" do
    test "are validated into one map keyed by name, with their owner" do
      principals =
        ContributionValidator.validate_contributions!([
          entry("ext/coating", [
            declaration(@principal, ["factory.material.import", "factory.item.view"])
          ])
        ])

      assert %{
               @principal => %{
                 name: @principal,
                 module_id: "ext/coating",
                 otp_app: :bilimbi_base_tenancy,
                 capabilities: ["factory.item.view", "factory.material.import"]
               }
             } = principals
    end

    test "nothing declared is an empty map" do
      assert ContributionValidator.validate_contributions!([]) == %{}
    end

    test "a name belongs to one module; a second declaration stops boot" do
      assert_raise ArgumentError, ~r/already declared by ext\/coating/, fn ->
        ContributionValidator.validate_contributions!([
          entry("ext/coating", [declaration(@principal)]),
          entry("ext/other", [declaration(@principal)])
        ])
      end
    end

    test "a malformed declaration stops boot" do
      for bad <- [
            declaration("line_import"),
            declaration("Coating.line_import"),
            declaration("coating..line"),
            declaration(String.duplicate("a.", 60) <> "b"),
            declaration(@principal, ["Factory.Import"]),
            declaration(@principal, ["factory.import", "factory.import"]),
            %{declaration(@principal) | description: " "},
            Map.put(declaration(@principal), :grant_all, true),
            Map.delete(declaration(@principal), :capabilities),
            "coating.line_import"
          ] do
        assert_raise ArgumentError, ~r/invalid system_principals contribution/, fn ->
          ContributionValidator.validate_contributions!([entry("ext/coating", [bad])])
        end
      end

      assert_raise ArgumentError, ~r/expected a list/, fn ->
        ContributionValidator.validate_contributions!([
          entry("ext/coating", declaration(@principal))
        ])
      end
    end

    test "an undeclared name is not a principal" do
      assert SystemPrincipals.declared?(@principal)
      refute SystemPrincipals.declared?("coating.other")
      refute SystemPrincipals.declared?(nil)
      assert {:error, :undeclared_system_principal} = SystemPrincipals.fetch("coating.other")
    end

    test "only code of the declaring module is bound to the name" do
      assert SystemPrincipals.declared_by?(@principal, Bilimbi.Base.Tenancy)
      refute SystemPrincipals.declared_by?(@principal, Enum)
      refute SystemPrincipals.declared_by?("coating.other", Bilimbi.Base.Tenancy)
    end
  end

  describe "a job's run as a principal" do
    test "resumes the declared principal in its company on a freshly proven tenant", %{
      operator: scope
    } do
      assert {:ok, token} = Authentication.delegate_system(scope, @principal, 10)
      assert {:ok, resumed} = Authentication.resume_system(token)

      assert Scope.tenant_id(resumed) == 41

      assert %Actor{type: :system, system_principal: @principal, company_id: 10, user_id: nil} =
               actor = Scope.actor(resumed)

      assert Actor.system?(actor)
      refute Actor.user?(actor)
      assert Actor.system_principal(actor) == @principal
      assert Actor.system_principal(Scope.actor(scope)) == nil
    end

    test "takes only the tenant from the enqueuing scope, never its user", %{operator: scope} do
      signed_in = Authentication.sign_in(scope, 7, 10)

      {:ok, token} = Authentication.delegate_system(signed_in, @principal, 11)
      {:ok, resumed} = Authentication.resume_system(token)

      assert %Actor{type: :system, user_id: nil, company_id: 11} = Scope.actor(resumed)
    end

    test "refuses an undeclared name or an invalid company", %{operator: scope} do
      assert {:error, :undeclared_system_principal} =
               Authentication.delegate_system(scope, "coating.other", 10)

      assert {:error, :invalid_company} = Authentication.delegate_system(scope, @principal, 0)
    end

    test "refuses a principal no longer declared when the job runs", %{operator: scope} do
      {:ok, token} = Authentication.delegate_system(scope, @principal, 10)

      install_principals!([])

      assert {:error, :undeclared_system_principal} = Authentication.resume_system(token)
    end

    test "refuses a tampered, foreign, expired, or user token", %{operator: scope} do
      {:ok, token} = Authentication.delegate_system(scope, @principal, 10)

      assert {:error, :invalid} = Authentication.resume_system(token <> "x")

      forged = Plug.Crypto.sign(String.duplicate("k", 64), "anything", {41, @principal, 10})
      assert {:error, :invalid} = Authentication.resume_system(forged)
      assert {:error, :expired} = Authentication.resume_system(token, max_age: -1)

      {:ok, user_token} = scope |> Authentication.sign_in(7, 10) |> Authentication.delegate()
      assert {:error, :invalid} = Authentication.resume_system(user_token)
      assert {:error, :invalid} = Authentication.resume(token)
    end

    test "fails when the tenant is gone by the time the job runs", %{operator: scope} do
      {:ok, token} = Authentication.delegate_system(scope, @principal, 10)

      Ecto.Adapters.SQL.query!(Repo, "UPDATE tenants SET deleted_at = now() WHERE id = 41", [])

      assert {:error, :soft_deleted} = Authentication.resume_system(token)
    end
  end

  describe "a principal is never a person" do
    test "cannot be signed in over, so it cannot be impersonated", %{operator: scope} do
      principal = principal_scope(scope)

      assert_raise ArgumentError, ~r/runs as coating.line_import/, fn ->
        Authentication.sign_in(principal, 7, 10)
      end

      assert_raise ArgumentError, fn ->
        Authentication.sign_in(principal, 8, 10,
          impersonator_id: 7,
          impersonation_session_id: "s1"
        )
      end
    end

    test "has no user to delegate", %{operator: scope} do
      assert {:error, :no_authenticated_actor} =
               scope |> principal_scope() |> Authentication.delegate()
    end
  end

  describe "a forged principal" do
    test "built as a struct literal is refused", %{operator: scope} do
      forged = %Scope{
        tenant: Scope.tenant(scope),
        actor: %Actor{type: :system, system_principal: @principal, company_id: 10, seal: "x"}
      }

      assert_raise ForgedActorError, fn -> Scope.actor(forged) end
    end

    test "named onto an anonymous system actor is refused", %{operator: scope} do
      promoted = %{scope | actor: %{scope.actor | system_principal: @principal, company_id: 10}}

      assert_raise ForgedActorError, fn -> Scope.actor(promoted) end
    end

    test "renamed, moved to another company, or given a user is refused", %{operator: scope} do
      principal = principal_scope(scope)
      actor = principal.actor

      for forged_actor <- [
            %{actor | system_principal: "coating.other"},
            %{actor | company_id: 99},
            %{actor | system_principal: nil, company_id: nil},
            %{actor | user_id: 7},
            %{actor | impersonator_id: 7, impersonation_session_id: "s1"},
            %{actor | type: :user}
          ] do
        assert_raise ForgedActorError, fn -> Scope.actor(%{principal | actor: forged_actor}) end
      end
    end

    test "moved onto another tenant's scope is refused", %{operator: operator, customer: customer} do
      principal = principal_scope(operator)

      assert_raise ForgedActorError, fn -> Scope.actor(%{customer | actor: principal.actor}) end
    end
  end

  defp principal_scope(scope) do
    {:ok, token} = Authentication.delegate_system(scope, @principal, 10)
    {:ok, resumed} = Authentication.resume_system(token)
    resumed
  end

  defp declaration(name, capabilities \\ ["factory.material.import"]) do
    %{
      name: name,
      description: "Imports coating line production records.",
      capabilities: capabilities
    }
  end

  defp entry(id, payload),
    do: %{descriptor: %{id: id, otp_app: :bilimbi_base_tenancy}, payload: payload}

  defp install_principals!(declarations) do
    ContributionRegistry.put_consumers_for_test!(
      %{
        system_principals:
          ContributionValidator.validate_contributions!([entry("ext/coating", declarations)])
      },
      nil
    )
  end
end
