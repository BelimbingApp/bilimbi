defmodule Bilimbi.Core.User.ActorVerifierTest do
  @moduledoc """
  The Core User half of ADR 0016's actor verifier, through the path a queued
  job takes: a token delegated from a signed-in scope, resumed by Base Tenancy
  with this verifier installed. Base Tenancy and Base Queue can only test the
  seam on doubles, because Base cannot reach Core.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.TestFixtures, as: SessionFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.ActorVerifier
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Ecto.Adapters.SQL

  @operator_id 91
  @target_id 92
  @session_id "borrowed-session"

  setup do
    UserFixtures.create_user_tables!()
    SessionFixtures.create_sessions_table!()

    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 41, name: "Other", code: "other"})

    UserFixtures.insert_user!(%{id: @operator_id, company_id: 73})

    UserFixtures.insert_user!(%{
      id: @target_id,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    ContributionRegistry.put_consumers_for_test!(%{actor_verifier: ActorVerifier}, nil)

    on_exit(&ContributionRegistry.clear_for_test!/0)

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "a job resumes as a user who still belongs to the company", %{scope: scope} do
    assert {:ok, resumed} = scope |> delegate(@target_id) |> Authentication.resume()
    assert %Actor{type: :user, user_id: @target_id, company_id: 73} = Scope.actor(resumed)
  end

  test "a job queued by a user who has since signed out still runs as them", %{scope: scope} do
    {:ok, _entry} =
      Session.put_session("own-session", "opaque", %{user_id: @target_id, last_activity: 0})

    token = delegate(scope, @target_id)

    :ok = Session.delete_session("own-session")

    assert {:ok, _resumed} = Authentication.resume(token)
  end

  test "a job for a deleted user is refused", %{scope: scope} do
    token = delegate(scope, @target_id)

    SQL.query!(Repo, "DELETE FROM users WHERE id = $1", [@target_id])

    assert {:error, :actor_refused} = Authentication.resume(token)
  end

  test "a job for a user moved out of the company is refused", %{scope: scope} do
    token = delegate(scope, @target_id)

    SQL.query!(Repo, "UPDATE users SET company_id = 74 WHERE id = $1", [@target_id])

    assert {:error, :actor_refused} = Authentication.resume(token)
  end

  describe "a job queued under impersonation" do
    setup %{scope: scope} do
      {:ok, _entry} =
        Session.put_session(@session_id, "opaque", %{user_id: @target_id, last_activity: 0})

      %{token: delegate(scope, @target_id, impersonator_id: @operator_id)}
    end

    test "runs while the impersonation is in progress", %{token: token} do
      assert {:ok, resumed} = Authentication.resume(token)

      assert %Actor{user_id: @target_id, impersonator_id: @operator_id} = Scope.actor(resumed)
    end

    test "is refused once the operator has left the impersonation", %{token: token} do
      # Leaving restores the operator on the same durable session.
      {:ok, _entry} =
        Session.put_session(@session_id, "opaque", %{user_id: @operator_id, last_activity: 0})

      assert {:error, :actor_refused} = Authentication.resume(token)
    end

    test "is refused once the impersonated session has signed out", %{token: token} do
      :ok = Session.delete_session(@session_id)

      assert {:error, :actor_refused} = Authentication.resume(token)
    end
  end

  defp delegate(scope, user_id, opts \\ []) do
    opts =
      if opts[:impersonator_id],
        do: Keyword.put(opts, :impersonation_session_id, @session_id),
        else: opts

    {:ok, token} = scope |> Authentication.sign_in(user_id, 73, opts) |> Authentication.delegate()
    token
  end
end
