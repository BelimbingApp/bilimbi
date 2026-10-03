defmodule Bilimbi.Base.Authz.LiveAuthorizationTest do
  @moduledoc """
  A LiveView re-asks Authz inside an event: the decision is the actor's
  current grants, never the capability list computed at mount.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication

  import Bilimbi.Base.Authz.TestFixtures

  @capability "admin.test.record.view"
  @unknown "admin.test.record.unknown"

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    {:ok, :stored} = Authz.put_principal_capability(scope(), 10, :user, 7, @capability, true)
    {:ok, actor} = scope() |> Authentication.sign_in(7, 10) |> Authz.scope_actor()

    %{actor: actor}
  end

  # The shape `BilimbiWeb.UserAuth` assigns: the sealed actor beside the
  # capability list rendered at mount.
  defp socket(actor, capabilities \\ [@capability]) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: %{actor: actor, capabilities: capabilities}
      },
      private: %{live_temp: %{}}
    }
  end

  defp revoke! do
    {:ok, :stored} = Authz.put_principal_capability(scope(), 10, :user, 7, @capability, false)
  end

  test "a held capability proceeds with the socket untouched", %{actor: actor} do
    socket = socket(actor)

    assert {:ok, ^socket} = LiveAuthorization.authorize_event(socket, @capability)
    assert LiveAuthorization.allowed_now?(socket.assigns.current_scope, @capability)
  end

  test "a grant revoked after mount is refused, flashed, and withheld from the page", %{
    actor: actor
  } do
    socket = socket(actor)
    revoke!()

    assert {:denied, denied} = LiveAuthorization.authorize_event(socket, @capability)
    assert denied.assigns.flash["error"] == LiveAuthorization.denied_message()
    assert denied.assigns.current_scope.capabilities == []

    assert [%DecisionLog{allowed: false, capability: @capability, actor_id: 7}] =
             Repo.all(DecisionLog)

    refute LiveAuthorization.allowed_now?(actor, @capability)
  end

  test "an any-of requirement needs one key now, and withholds all of them when none holds",
       %{actor: actor} do
    requirement = {:any_of, [@unknown, @capability]}
    socket = socket(actor, [@unknown, @capability])

    assert {:ok, _} = LiveAuthorization.authorize_event(socket, requirement)

    revoke!()

    assert {:denied, denied} = LiveAuthorization.authorize_event(socket, requirement)
    assert denied.assigns.current_scope.capabilities == []
  end

  test "a scope that names nobody is refused without a decision to log" do
    socket = %{socket(nil) | assigns: %{__changed__: %{}, flash: %{}}}

    assert {:denied, denied} = LiveAuthorization.authorize_event(socket, @capability)
    assert denied.assigns.flash["error"] == LiveAuthorization.denied_message()
    refute LiveAuthorization.allowed_now?(nil, @capability)
    assert Repo.all(DecisionLog) == []
  end

  test "an operation must name its capability", %{actor: actor} do
    for requirement <- [nil, "", {:any_of, []}, {:any_of, [@capability, @capability]}] do
      assert_raise ArgumentError, fn ->
        LiveAuthorization.authorize_event(socket(actor), requirement)
      end

      assert_raise ArgumentError, fn -> LiveAuthorization.allowed_now?(actor, requirement) end
    end
  end
end
