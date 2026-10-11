defmodule Bilimbi.Base.Workflow.TransitionOutboxTest do
  use Bilimbi.Base.Database.DataCase, async: false
  import Ecto.Query
  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Base.Workflow.{OutboxSchema, TestListener}
  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  @oban Bilimbi.Base.Queue.Oban

  setup do
    create_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    start_supervised!(TestListener)
    system = TenancyFixtures.scope()
    actor = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    assert {:ok, :seeded} = Workflow.seed_definitions()
    %{scope: actor, subject: subject!(), system: system}
  end

  test "a committed transition writes one compatible outbox row and is delivered after commit",
       c do
    assert {:ok, %{history: history}} =
             Workflow.transition(c.scope, c.subject, "review", %{
               comment: "Ready",
               metadata: %{"fact" => true}
             })

    assert [row] = Repo.all(OutboxSchema)
    assert row.event_key == "workflow.transition.completed:#{history.id}"
    assert row.event_type == "workflow.transition.completed"
    assert row.attempts == 0 and is_nil(row.delivered_at) and is_nil(row.lease_token)

    assert %{
             "model_class" => "example.record",
             "model_id" => subject_id,
             "subject_type" => "example.record",
             "tenant_id" => 1,
             "transition_id" => transition_id,
             "history_id" => history_id,
             "context" => %{"actor" => %{"type" => "user", "id" => 7}, "comment" => "Ready"},
             "payload" => facts
           } = row.payload

    assert subject_id == c.subject.id and history_id == history.id and is_integer(transition_id)

    assert %{
             "flow" => "example_flow",
             "flow_id" => ^subject_id,
             "from_status" => "draft",
             "to_status" => "review",
             "actor_id" => 7,
             "comment" => "Ready",
             "metadata" => %{"fact" => true},
             "transitioned_at" => transitioned_at
           } = facts

    assert {:ok, _, 0} = DateTime.from_iso8601(transitioned_at)
    assert row.payload["history_snapshot"]["status"] == "review"
    assert row.payload["transition_snapshot"]["to_code"] == "review"

    # The immediate attempt is the job the transaction enqueued.
    assert %{success: 1} = Oban.drain_queue(@oban, queue: :default)

    assert [%{scope: scope, event: event}] = TestListener.deliveries()
    assert Bilimbi.Base.Tenancy.Scope.tenant_id(scope) == 1
    assert Bilimbi.Base.Tenancy.Scope.actor(scope).type == :system
    assert event.event_key == row.event_key
    assert event.subject == %{type: "example.record", id: c.subject.id}
    assert event.flow == "example_flow"
    assert event.from_status == "draft" and event.to_status == "review"
    assert event.actor == %{type: "user", id: 7}
    assert event.context.comment == "Ready" and event.context.metadata == %{"fact" => true}
    assert event.history["id"] == history.id
    assert event.transition["from_code"] == "draft"
    assert %NaiveDateTime{} = event.transitioned_at
    assert event.attempt == 1

    assert %OutboxSchema{attempts: 1, lease_token: nil, last_error: nil} = row = reload(row)
    assert %NaiveDateTime{} = row.delivered_at

    # Delivered rows are not delivered twice.
    assert {:ok, %{delivered: 0, deferred: 0, skipped: 0}} = Workflow.deliver_transition_events()
    assert length(TestListener.deliveries()) == 1
  end

  test "a refused transition leaves neither an outbox row nor a delivery job", c do
    private = subject!(%{marker: "private"})
    assert {:error, :owner_refused} = Workflow.transition(c.scope, private, "closed")
    assert {:error, :invalid_edge} = Workflow.transition(c.scope, c.subject, "unknown")
    assert Repo.all(OutboxSchema) == []
    assert %{} = Oban.drain_queue(@oban, queue: :default)
    assert TestListener.deliveries() == []
  end

  test "a refusing listener defers the event with backoff until it accepts", c do
    TestListener.mode({:error, :mailbox_full})
    assert {:ok, _} = Workflow.transition(c.scope, c.subject, "review")
    assert %{success: 1} = Oban.drain_queue(@oban, queue: :default)

    assert [row] = Repo.all(OutboxSchema)
    assert row.attempts == 1 and is_nil(row.delivered_at) and is_nil(row.lease_token)
    assert row.last_error =~ "example.notify" and row.last_error =~ "mailbox_full"
    assert NaiveDateTime.compare(row.available_at, now()) == :gt

    # Not due yet: nothing is attempted.
    assert {:ok, %{delivered: 0, deferred: 0}} = Workflow.deliver_transition_events()
    assert length(TestListener.deliveries()) == 1

    TestListener.mode(:ok)
    make_due!(row)
    assert {:ok, %{delivered: 1, deferred: 0}} = Workflow.deliver_transition_events()
    assert %OutboxSchema{attempts: 2, last_error: nil} = row = reload(row)
    assert %NaiveDateTime{} = row.delivered_at
    assert [_first, second] = TestListener.deliveries()
    assert second.event.attempt == 2 and second.event.to_status == "review"
  end

  test "a crashing or ill-behaved listener is deferred with the reason kept", c do
    TestListener.mode(:raise)
    assert {:ok, _} = Workflow.transition(c.scope, c.subject, "review")
    assert %{success: 1} = Oban.drain_queue(@oban, queue: :default)
    assert [row] = Repo.all(OutboxSchema)
    assert row.last_error =~ "listener outage" and is_nil(row.delivered_at)

    TestListener.mode(:garbage)
    make_due!(row)
    assert {:ok, %{deferred: 1}} = Workflow.deliver_transition_events()
    assert reload(row).last_error =~ "invalid_listener_result"
    assert reload(row).attempts == 2
  end

  test "a live lease is skipped and an expired lease is claimed again", c do
    assert {:ok, _} = Workflow.transition(c.scope, c.subject, "review")
    assert [row] = Repo.all(OutboxSchema)

    row
    |> Ecto.Changeset.change(%{lease_token: "other-worker", lease_expires_at: in_seconds(120)})
    |> Repo.update!()

    assert {:ok, %{delivered: 0, deferred: 0, skipped: 0}} = Workflow.deliver_transition_events()
    assert TestListener.deliveries() == []

    row
    |> Ecto.Changeset.change(%{lease_expires_at: in_seconds(-1)})
    |> Repo.update!()

    assert {:ok, %{delivered: 1}} = Workflow.deliver_transition_events()
    assert [%{event: %{attempt: 1}}] = TestListener.deliveries()
    assert reload(row).lease_token == nil
  end

  test "a retained Belimbing event is delivered through the adopted subject's binding", c do
    SQL.query!(Repo, "UPDATE base_workflow SET model_class = $1", ["Legacy\\Example\\Record"])
    legacy_row = insert_legacy_event!(c.subject.id, 1)

    # Nothing is adopted yet: the row is deferred, never guessed.
    assert {:ok, %{deferred: 1}} = Workflow.deliver_transition_events()
    assert reload(legacy_row).last_error =~ "subject_unbound"
    assert TestListener.deliveries() == []

    alias_ref = %{type: "Legacy\\Example\\Record", id: to_string(c.subject.id)}
    assert {:ok, _} = Workflow.adopt_subject(c.scope, alias_ref)
    make_due!(legacy_row)

    assert {:ok, %{delivered: 1}} = Workflow.deliver_transition_events()
    assert [%{scope: scope, event: event}] = TestListener.deliveries()
    assert Bilimbi.Base.Tenancy.Scope.tenant_id(scope) == 1
    assert event.subject == %{type: "example.record", id: c.subject.id}
    assert event.event_key == "workflow.transition.completed:901"
    assert event.actor == %{type: "user", id: 5}
    assert event.context.comment == "Legacy comment"
    assert event.transitioned_at == ~N[2026-01-01 00:00:00]
    assert event.attempt == 2
    assert reload(legacy_row).payload["model_class"] == "Legacy\\Example\\Record"
  end

  test "an event bound to another tenant's subject is delivered under that tenant", c do
    other = subject!(%{tenant_id: 2, company_id: 20})
    other_scope = Authentication.sign_in(TenancyFixtures.scope(2), 8, 20)

    # draft -> closed carries no capability, so the other tenant needs no grant.
    assert {:ok, _} = Workflow.transition(other_scope, other, "closed")
    assert {:ok, _} = Workflow.transition(c.scope, c.subject, "review")
    assert %{success: 2} = Oban.drain_queue(@oban, queue: :default)

    tenants =
      TestListener.deliveries()
      |> Enum.map(&{&1.event.subject.id, Bilimbi.Base.Tenancy.Scope.tenant_id(&1.scope)})
      |> Enum.sort()

    assert tenants == Enum.sort([{other.id, 2}, {c.subject.id, 1}])
  end

  test "delivery limits are bounded" do
    assert_raise ArgumentError, fn -> Workflow.deliver_transition_events(limit: 0) end
    assert_raise ArgumentError, fn -> Workflow.deliver_transition_events(limit: 1001) end
  end

  defp insert_legacy_event!(subject_id, _tenant_id) do
    payload = %{
      "model_class" => "Legacy\\Example\\Record",
      "model_id" => subject_id,
      "model_key_name" => "id",
      "model_snapshot" => %{"id" => subject_id, "status" => "review"},
      "transition_id" => 77,
      "transition_snapshot" => %{"id" => 77, "flow" => "example_flow", "from_code" => "draft"},
      "history_id" => 901,
      "history_snapshot" => %{"id" => 901, "actor_id" => 5, "actor_type" => "user"},
      "context" => %{
        "actor" => %{"type" => "user", "id" => 5, "company_id" => 10, "attributes" => []},
        "comment" => "Legacy comment"
      },
      "payload" => %{
        "flow" => "example_flow",
        "flow_model" => "Legacy\\Example\\Record",
        "flow_id" => subject_id,
        "from_status" => "draft",
        "to_status" => "review",
        "actor_id" => 5,
        "comment" => "Legacy comment",
        "transitioned_at" => "2026-01-01T00:00:00+00:00"
      }
    }

    %OutboxSchema{
      event_key: "workflow.transition.completed:901",
      event_type: "workflow.transition.completed",
      payload: payload,
      attempts: 0,
      available_at: ~N[2026-01-01 00:00:00],
      created_at: ~N[2026-01-01 00:00:00],
      updated_at: ~N[2026-01-01 00:00:00]
    }
    |> Repo.insert!()
  end

  defp make_due!(row) do
    Repo.update_all(from(o in OutboxSchema, where: o.id == ^row.id),
      set: [available_at: in_seconds(-1)]
    )
  end

  defp reload(row), do: Repo.get!(OutboxSchema, row.id)
  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  defp in_seconds(seconds), do: NaiveDateTime.add(now(), seconds)
end
