defmodule Bilimbi.Base.Authz.ScopeActorTest do
  @moduledoc """
  "May the person performing this do it?" is asked of the scope, whose actor
  Bilimbi's authentication edge sealed. The answer cannot be steered by naming
  somebody else, and system work — which names nobody — is never allowed.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.AuthorizationDeniedError
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.ForgedActorError

  import Bilimbi.Base.Authz.TestFixtures

  @capability "admin.test.record.view"

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope(), 10, :user, 7, @capability, true)

    :ok
  end

  test "the signed-in user's own grants decide, and the decision log names them" do
    approver = Authentication.sign_in(scope(), 7, 10)

    assert {:ok, %Authz.Actor{type: :user, id: 7, company_id: 10}} = Authz.scope_actor(approver)
    assert Authz.can(approver, @capability).allowed
    assert :ok = Authz.authorize!(approver, @capability)

    logs = Repo.all(DecisionLog)
    assert logs != []
    assert Enum.all?(logs, &(&1.actor_type == "user" and &1.actor_id == 7))
  end

  test "another signed-in user is judged on their own grants, not the granted user's" do
    other = Authentication.sign_in(scope(), 9, 10)

    decision = Authz.can(other, @capability)
    refute decision.allowed
    assert decision.reason == :denied_missing_capability
  end

  test "a system scope names nobody and is denied without a principal to log" do
    assert {:error, :no_authenticated_actor} = Authz.scope_actor(scope())

    decision = Authz.can(scope(), @capability)
    refute decision.allowed
    assert decision.reason == :denied_no_authenticated_actor

    assert_raise AuthorizationDeniedError, fn -> Authz.authorize!(scope(), @capability) end
    assert Repo.all(DecisionLog) == []
  end

  test "an actor forged onto the scope is refused before any grant is read" do
    system = scope()
    forged = %{system | actor: %{system.actor | type: :user, user_id: 7, company_id: 10}}

    assert_raise ForgedActorError, fn -> Authz.can(forged, @capability) end
    assert_raise ForgedActorError, fn -> Authz.scope_actor(forged) end
    assert Repo.all(DecisionLog) == []
  end
end
