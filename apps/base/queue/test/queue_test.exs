defmodule Bilimbi.Base.QueueTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Queue.TestWorkers.Success
  alias Bilimbi.Base.Queue.TestWorkers.Unique
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Ecto.Multi

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    :ok
  end

  test "enqueue returns a stable reference without transport state" do
    assert {:ok,
            %JobRef{
              id: id,
              worker_id: "test/success",
              state: :available,
              conflict?: false
            }} = Queue.enqueue(Success, %{"value" => 7})

    assert is_integer(id) and id > 0

    refute Map.has_key?(
             Map.from_struct(Queue.enqueue(Success, %{"value" => 8}) |> elem(1)),
             :args
           )
  end

  test "enqueue excludes Oban job data from audit mutations" do
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()

    {:ok, scope} = Tenancy.scope(41)
    scope = Authentication.sign_in(scope, 7, 10)
    assert {:ok, %JobRef{}} = Queue.enqueue(Success, %{"value" => 7})

    assert Repo.aggregate(MutationSchema, :count, :id) == 0

    assert {:ok, %JobRef{id: delegated_id}} =
             Queue.enqueue_for(scope, Success, %{"value" => 8})

    delegated_job = Repo.get!(Oban.Job, delegated_id)
    assert is_binary(delegated_job.meta["bilimbi_delegated_actor"])

    assert Repo.aggregate(MutationSchema, :count, :id) == 0

    refute Repo.exists?(
             from(mutation in MutationSchema,
               where:
                 like(
                   fragment("to_jsonb(?)::text", mutation),
                   ^"%#{delegated_job.meta["bilimbi_delegated_actor"]}%"
                 )
             )
           )
  end

  test "enqueue rejects unsupported workers and non-JSON-safe or oversized arguments" do
    initial_count = Repo.aggregate(Oban.Job, :count, :id)

    assert {:error, :unsupported_worker} = Queue.enqueue(String, %{"value" => 1})
    assert {:error, :invalid_args} = Queue.enqueue(Success, %{value: 1})
    assert {:error, :invalid_args} = Queue.enqueue(Success, %{"value" => self()})
    assert {:error, :invalid_args} = Queue.enqueue(Success, %{"wrong" => 1})

    assert {:error, :invalid_args} =
             Queue.enqueue(Success, %{"value" => String.duplicate("x", 16_385)})

    assert Repo.aggregate(Oban.Job, :count, :id) == initial_count
  end

  test "transactional enqueue commits and rolls back with the caller's business operation" do
    assert {:ok, %{job: %JobRef{id: committed_id}}} =
             Multi.new()
             |> Queue.enqueue(:job, Success, %{"value" => 1})
             |> Repo.transaction()

    assert Repo.exists?(from(job in Oban.Job, where: job.id == ^committed_id))

    assert {:error, :stop, :rollback, _changes} =
             Multi.new()
             |> Queue.enqueue(:job, Success, %{"value" => 2})
             |> Multi.run(:stop, fn _repo, _changes -> {:error, :rollback} end)
             |> Repo.transaction()

    assert Repo.aggregate(Oban.Job, :count, :id) == 1
  end

  test "unique insertion reports transport conflict without claiming business idempotency" do
    assert {:ok, %JobRef{id: id, conflict?: false}} =
             Queue.enqueue(Unique, %{"business_id" => 42})

    assert {:ok, %JobRef{id: ^id, conflict?: true}} =
             Queue.enqueue(Unique, %{"business_id" => 42})
  end

  test "cancel, retry, and invalid IDs return bounded outcomes" do
    assert {:error, :invalid_job_id} = Queue.cancel(0)
    assert {:error, :invalid_job_id} = Queue.job_state(0)
    assert {:error, :invalid_job_id} = Queue.retry("1")
    assert {:error, :not_found} = Queue.cancel(9_999_999)
    assert {:error, :not_found} = Queue.job_state(9_999_999)

    assert {:ok, %JobRef{id: id}} = Queue.enqueue(Success, %{"value" => 1})
    assert {:ok, :available} = Queue.job_state(id)
    assert :ok = Queue.cancel(id)
    assert {:ok, :cancelled} = Queue.job_state(id)
    assert :ok = Queue.retry(id)
    assert {:ok, :available} = Queue.job_state(id)
  end
end
