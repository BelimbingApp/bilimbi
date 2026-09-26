defmodule Bilimbi.Base.Tenancy.ScopeActorTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.ForgedActorError
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    {:ok, operator} = Tenancy.scope(41)
    {:ok, customer} = Tenancy.scope(42)
    %{operator: operator, customer: customer}
  end

  describe "a tenant-only scope" do
    test "is performed by the explicit system actor", %{operator: scope} do
      assert %Actor{type: :system, user_id: nil, company_id: nil, impersonator_id: nil} =
               actor = Scope.actor(scope)

      assert Actor.system?(actor)
      refute Actor.user?(actor)
    end

    test "for_tenant/1 builds the same system actor" do
      identity = %Identity{id: 41, name: "Operator", status: "active", is_platform_operator: true}

      assert %Actor{type: :system} = identity |> Scope.for_tenant() |> Scope.actor()
    end

    test "has no user to delegate to a job", %{operator: scope} do
      assert {:error, :no_authenticated_actor} = Authentication.delegate(scope)
    end
  end

  describe "the authentication edge" do
    test "attaches the signed-in user, and the operator behind an impersonation", %{
      operator: scope
    } do
      signed_in = Authentication.sign_in(scope, 7, 10)

      assert %Actor{type: :user, user_id: 7, company_id: 10, impersonator_id: nil} =
               Scope.actor(signed_in)

      assert Scope.tenant_id(signed_in) == 41

      impersonated = Authentication.sign_in(scope, 8, 10, impersonator_id: 7)

      assert %Actor{type: :user, user_id: 8, impersonator_id: 7} = Scope.actor(impersonated)
    end

    test "sets the actor once and never changes it", %{operator: scope} do
      signed_in = Authentication.sign_in(scope, 7, 10)

      assert_raise ArgumentError, ~r/set once/, fn ->
        Authentication.sign_in(signed_in, 8, 10)
      end
    end
  end

  describe "a forged actor" do
    test "built as a struct literal is refused", %{operator: scope} do
      forged = %Scope{
        tenant: Scope.tenant(scope),
        actor: %Actor{type: :user, user_id: 7, company_id: 10, seal: "trust me"}
      }

      assert_raise ForgedActorError, fn -> Scope.actor(forged) end
    end

    test "changed by a struct update is refused", %{operator: scope} do
      signed_in = Authentication.sign_in(scope, 7, 10)
      actor = signed_in.actor

      for forged_actor <- [
            %{actor | user_id: 99},
            %{actor | company_id: 99},
            %{actor | impersonator_id: 99},
            %{actor | type: :system}
          ] do
        assert_raise ForgedActorError, fn -> Scope.actor(%{signed_in | actor: forged_actor}) end
      end
    end

    test "promoting a system actor to a user is refused", %{operator: scope} do
      promoted = %{scope | actor: %{scope.actor | type: :user, user_id: 7, company_id: 10}}

      assert_raise ForgedActorError, fn -> Scope.actor(promoted) end
    end

    test "moved onto another tenant's scope is refused", %{operator: operator, customer: customer} do
      signed_in = Authentication.sign_in(operator, 7, 10)

      assert_raise ForgedActorError, fn -> Scope.actor(%{customer | actor: signed_in.actor}) end
      assert_raise ForgedActorError, fn -> Scope.actor(%{signed_in | tenant: customer.tenant}) end
    end

    test "missing or of the wrong shape is refused", %{operator: scope} do
      assert_raise ForgedActorError, fn -> Scope.actor(%{scope | actor: nil}) end
      assert_raise ForgedActorError, fn -> Scope.actor(%{scope | actor: %{type: :system}}) end
    end

    test "never shows its seal when inspected", %{operator: scope} do
      signed_in = Authentication.sign_in(scope, 7, 10)

      refute inspect(signed_in) =~ "seal"
      assert inspect(signed_in) =~ "user_id: 7"
    end
  end

  describe "delegation to a background job" do
    test "resumes the same user on a freshly proven tenant", %{operator: scope} do
      signed_in = Authentication.sign_in(scope, 8, 10, impersonator_id: 7)

      assert {:ok, token} = Authentication.delegate(signed_in)
      assert {:ok, resumed} = Authentication.resume(token)

      assert Scope.tenant_id(resumed) == 41
      assert Scope.actor(resumed) == Scope.actor(signed_in)
    end

    test "refuses a tampered, foreign, or expired token", %{operator: scope} do
      {:ok, token} = scope |> Authentication.sign_in(7, 10) |> Authentication.delegate()

      assert {:error, :invalid} = Authentication.resume(token <> "x")
      assert {:error, :invalid} = Authentication.resume("not a token")

      forged = Plug.Crypto.sign(String.duplicate("k", 64), "anything", {41, 1, 10, nil})
      assert {:error, :invalid} = Authentication.resume(forged)

      assert {:error, :expired} = Authentication.resume(token, max_age: -1)
    end

    test "fails when the tenant is gone by the time the job runs", %{operator: scope} do
      {:ok, token} = scope |> Authentication.sign_in(7, 10) |> Authentication.delegate()

      Ecto.Adapters.SQL.query!(
        Bilimbi.Base.Repo,
        "UPDATE tenants SET deleted_at = now() WHERE id = 41",
        []
      )

      assert {:error, :soft_deleted} = Authentication.resume(token)
    end
  end
end
