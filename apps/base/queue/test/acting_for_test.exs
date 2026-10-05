defmodule Bilimbi.Base.Queue.ActingForTest do
  @moduledoc """
  A job enqueued for a signed-in user runs as that user: its execution carries
  the user's scope, rebuilt from a token only the enqueuing scope could sign.
  Nothing a caller puts in the arguments, and no edit to the token, makes a
  job run as someone else.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Queue.TestActorVerifier
  alias Bilimbi.Base.Queue.TestWorkers.ActingFor
  alias Bilimbi.Base.Queue.TestWorkers.Unique
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    {:ok, system_scope} = Tenancy.scope(41)

    install_verifier!(TestActorVerifier)
    on_exit(&ContributionRegistry.clear_for_test!/0)

    %{system_scope: system_scope, user_scope: Authentication.sign_in(system_scope, 7, 10)}
  end

  test "the job runs as the user who enqueued it", %{user_scope: user_scope} do
    assert {:ok, %JobRef{id: id}} = Queue.enqueue_for(user_scope, ActingFor, %{"value" => 1})

    job = Repo.get!(Oban.Job, id)
    assert job.args == %{"value" => 1}

    assert :ok = perform(job)
    assert_received {:performed, %Execution{scope: %Scope{} = scope}}

    assert Scope.tenant_id(scope) == 41
    assert %Actor{type: :user, user_id: 7, company_id: 10} = Scope.actor(scope)
  end

  test "an ordinary job is system work with no scope to act as", %{system_scope: system_scope} do
    assert {:error, :no_authenticated_actor} =
             Queue.enqueue_for(system_scope, ActingFor, %{"value" => 1})

    assert {:ok, %JobRef{id: id}} = Queue.enqueue(ActingFor, %{"value" => 1})
    assert :ok = id |> then(&Repo.get!(Oban.Job, &1)) |> perform()
    assert_received {:performed, %Execution{scope: nil}}
  end

  test "arguments cannot carry an actor into the job", %{user_scope: user_scope} do
    {:ok, token} = Authentication.delegate(user_scope)

    assert {:error, :invalid_args} =
             Queue.enqueue(ActingFor, %{"bilimbi_delegated_actor" => token})

    assert {:ok, %JobRef{id: id}} =
             Queue.enqueue(ActingFor, %{"value" => 1, "bilimbi_delegated_actor" => token})

    job = Repo.get!(Oban.Job, id)
    refute Map.has_key?(job.args, "bilimbi_delegated_actor")

    assert :ok = perform(job)
    assert_received {:performed, %Execution{scope: nil}}
  end

  test "a tampered or foreign token cancels the job before it runs as anyone", %{
    user_scope: user_scope
  } do
    {:ok, %JobRef{id: id}} = Queue.enqueue_for(user_scope, ActingFor, %{"value" => 1})
    job = Repo.get!(Oban.Job, id)
    token = job.meta["bilimbi_delegated_actor"]

    foreign = Plug.Crypto.sign(String.duplicate("k", 64), "anything", {41, 99, 10, nil})

    for meta <- [
          %{job.meta | "bilimbi_delegated_actor" => token <> "x"},
          %{job.meta | "bilimbi_delegated_actor" => foreign},
          %{job.meta | "bilimbi_delegated_actor" => %{"user_id" => 99}}
        ] do
      assert {:cancel, :delegated_actor_unavailable} = perform(%{job | meta: meta})
      refute_received {:performed, _execution}
    end
  end

  test "a job whose tenant is gone when it runs is cancelled", %{user_scope: user_scope} do
    {:ok, %JobRef{id: id}} = Queue.enqueue_for(user_scope, ActingFor, %{"value" => 1})

    Ecto.Adapters.SQL.query!(Repo, "UPDATE tenants SET deleted_at = now() WHERE id = 41", [])

    assert {:cancel, :delegated_actor_unavailable} =
             id |> then(&Repo.get!(Oban.Job, &1)) |> perform()

    refute_received {:performed, _execution}
  end

  test "a user the verifier no longer proves is refused before the job runs", %{
    user_scope: user_scope
  } do
    {:ok, %JobRef{id: id}} = Queue.enqueue_for(user_scope, ActingFor, %{"value" => 1})

    Process.put(:actor_verifier_answer, {:error, :user_not_found})

    assert {:cancel, :delegated_actor_refused} =
             id |> then(&Repo.get!(Oban.Job, &1)) |> perform()

    refute_received {:performed, _execution}
  end

  test "with no verifier installed, no job runs as a user", %{user_scope: user_scope} do
    {:ok, %JobRef{id: id}} = Queue.enqueue_for(user_scope, ActingFor, %{"value" => 1})

    install_verifier!(nil)

    assert {:cancel, :no_actor_verifier} = id |> then(&Repo.get!(Oban.Job, &1)) |> perform()
    refute_received {:performed, _execution}
  end

  test "a unique worker cannot act for a user, so no duplicate runs as someone else", %{
    system_scope: system_scope,
    user_scope: user_scope
  } do
    other_scope = Authentication.sign_in(system_scope, 8, 10)

    assert {:error, :unique_worker} =
             Queue.enqueue_for(user_scope, Unique, %{"business_id" => 1})

    assert {:error, :unique_worker} =
             Queue.enqueue_for(other_scope, Unique, %{"business_id" => 1})

    assert {:ok, %JobRef{conflict?: false}} = Queue.enqueue(Unique, %{"business_id" => 1})

    assert {:error, :unique_worker} =
             Queue.enqueue_for(user_scope, Unique, %{"business_id" => 1})

    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  defp perform(job), do: ActingFor.__queue_worker__().adapter.perform(job)

  defp install_verifier!(verifier) do
    ContributionRegistry.put_consumers_for_test!(%{actor_verifier: verifier}, nil)
  end
end
