defmodule Bilimbi.Base.WorkflowTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.{Authentication, ForgedActorError}
  alias Bilimbi.Base.Workflow.{BindingSchema, EdgeSchema, HistorySchema}
  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    create_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    system = Bilimbi.Base.Authz.TestFixtures.scope()
    actor = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    assert {:ok, :seeded} = Workflow.seed_definitions()
    %{scope: actor, subject: subject!(), system: system}
  end

  test "commits owner effects, context, scoped history and audit together", %{
    scope: scope,
    subject: subject
  } do
    assert {:ok, initial} = Workflow.record_initial(scope, subject)

    assert {:ok, outcome} =
             Workflow.transition(scope, subject, "review", %{
               comment: "Ready",
               attachments: ["evidence"],
               metadata: %{"fact" => true}
             })

    assert outcome.from == "draft"
    assert outcome.to == "review"
    assert state(subject.id).status == "review"
    assert state(subject.id).marker == "action_ran"

    assert {:ok, %{entries: [^initial, history], next_cursor: nil}} =
             Workflow.history(scope, subject)

    assert history.comment == "Ready"
    assert history.attachments == ["evidence"]
    assert history.actor_type == "user" and history.actor_id == 7
    assert is_integer(history.tat)

    assert [["user", 7, 1, payload]] =
             SQL.query!(
               Repo,
               "SELECT actor_type, actor_id, tenant_id, payload FROM base_audit_actions WHERE event = 'workflow.transition.completed'",
               []
             ).rows

    assert payload["subject_type"] == "example.record"
    assert payload["history_id"] == history.id
  end

  test "invalid and inactive edges leave no binding or history", %{scope: scope, subject: subject} do
    for to <- ["draft", "retired", "unknown"],
        do: assert({:error, :invalid_edge} = Workflow.transition(scope, subject, to))

    assert state(subject.id).status == "draft"
    assert Repo.all(HistorySchema) == [] and Repo.all(BindingSchema) == []
  end

  test "missing capability and owner policy refuse", %{
    scope: scope,
    subject: subject,
    system: system
  } do
    actor = Authentication.sign_in(system, 9, 10)
    assert {:error, :missing_capability} = Workflow.transition(actor, subject, "review")
    private = subject!(%{marker: "private"})
    assert {:error, :owner_refused} = Workflow.transition(scope, private, "closed")
    assert state(subject.id).marker == "original"
    assert Repo.all(HistorySchema) == []
  end

  test "cross-tenant subjects and history refuse", %{scope: scope} do
    foreign = subject!(%{tenant_id: 2})
    assert {:error, :subject_not_found} = Workflow.transition(scope, foreign, "closed")
    assert {:error, :subject_not_found} = Workflow.adopt_subject(scope, foreign)
    assert {:error, :subject_not_found} = Workflow.history(scope, foreign)
    assert Repo.all(HistorySchema) == []
  end

  test "guard and action refusals roll back all effects", %{scope: scope, subject: subject} do
    assert {:error, :guard_refused} =
             Workflow.transition(scope, subject, "review", %{input: %{"refuse_guard" => true}})

    assert {:error, :action_refused} =
             Workflow.transition(scope, subject, "review", %{input: %{"refuse_action" => true}})

    assert state(subject.id).status == "draft" and state(subject.id).marker == "original"
    assert Repo.all(HistorySchema) == [] and Repo.all(BindingSchema) == []
    assert SQL.query!(Repo, "SELECT count(*) FROM base_audit_actions", []).rows == [[0]]
  end

  test "forged actor, anonymous system and caller authority refuse", %{
    scope: scope,
    system: system,
    subject: subject
  } do
    assert {:error, :no_authenticated_actor} = Workflow.transition(system, subject, "closed")

    assert {:error, :invalid_context} =
             Workflow.transition(scope, subject, "closed", %{actor_id: 7})

    assert_raise ForgedActorError, fn ->
      Workflow.transition(%{scope | actor: %{scope.actor | user_id: 9}}, subject, "closed")
    end

    assert state(subject.id).status == "draft"
  end

  test "legacy aliases and ambiguous actors retain original history", %{
    scope: scope,
    subject: subject
  } do
    SQL.query!(Repo, "UPDATE base_workflow SET model_class = $1", ["Legacy\\Example\\Record"])

    SQL.query!(
      Repo,
      "UPDATE base_workflow_status_transitions SET guard_class = $1, action_class = $2 WHERE to_code = 'review'",
      ["Legacy\\Example\\Guard", "Legacy\\Example\\Action"]
    )

    for {type, id, status} <- [
          {nil, 1, "old_state"},
          {"agent", 1, "draft"},
          {"guest", nil, "draft"}
        ] do
      SQL.query!(
        Repo,
        """
        INSERT INTO base_workflow_status_history (flow, flow_id, status, actor_type, actor_id, metadata, transitioned_at)
        VALUES ('example_flow', $1, $2, $3, $4, '[1,{"legacy":true}]', '2026-01-01 00:00:00')
        """,
        [subject.id, status, type, id]
      )
    end

    alias_ref = %{subject | type: "Legacy\\Example\\Record", id: to_string(subject.id)}
    assert {:ok, %{entries: []}} = Workflow.history(scope, alias_ref)
    assert {:ok, _} = Workflow.adopt_subject(scope, alias_ref)
    assert {:ok, %{entries: facts}} = Workflow.history(scope, subject)
    assert Enum.map(facts, & &1.actor_type) == [nil, "agent", "guest"]
    assert Enum.map(facts, & &1.status) == ["old_state", "draft", "draft"]
    assert Enum.all?(facts, &(&1.metadata == [1, %{"legacy" => true}]))
    assert {:ok, _} = Workflow.transition(scope, alias_ref, "review")

    assert SQL.query!(Repo, "SELECT model_class FROM base_workflow", []).rows == [
             ["Legacy\\Example\\Record"]
           ]

    assert SQL.query!(
             Repo,
             "SELECT guard_class FROM base_workflow_status_transitions WHERE to_code = 'review'",
             []
           ).rows == [["Legacy\\Example\\Guard"]]
  end

  test "inactive legacy flows may bind history but refuse new transitions", %{
    scope: scope,
    subject: subject
  } do
    SQL.query!(Repo, "UPDATE base_workflow SET is_active = false", [])

    SQL.query!(
      Repo,
      """
      INSERT INTO base_workflow_status_history (flow, flow_id, status, transitioned_at)
      VALUES ('example_flow', $1, 'old_state', '2026-01-01 00:00:00')
      """,
      [subject.id]
    )

    assert {:ok, _} = Workflow.adopt_subject(scope, subject)
    assert {:ok, %{entries: [%{status: "old_state"}]}} = Workflow.history(scope, subject)
    assert {:error, :flow_unavailable} = Workflow.transition(scope, subject, "closed")
    assert state(subject.id).status == "draft"
  end

  test "unknown stored hooks fail closed", %{scope: scope, subject: subject} do
    SQL.query!(
      Repo,
      "UPDATE base_workflow_status_transitions SET guard_class = 'Unknown\\Guard' WHERE to_code = 'review'",
      []
    )

    assert {:error, :adapter_unavailable} = Workflow.transition(scope, subject, "review")
    assert state(subject.id).status == "draft" and Repo.all(HistorySchema) == []
  end

  test "initial/comments and timestamp ties paginate as separate facts", %{
    scope: scope,
    subject: subject
  } do
    assert {:ok, _} = Workflow.record_initial(scope, subject)
    assert {:error, :history_exists} = Workflow.record_initial(scope, subject)
    assert {:ok, _} = Workflow.record_comment(scope, subject, %{comment: "A note"})
    assert {:error, :comment_required} = Workflow.record_comment(scope, subject, %{})

    assert {:ok, %{entries: [first], next_cursor: cursor}} =
             Workflow.history(scope, subject, limit: 1)

    assert {:ok, %{entries: [second], next_cursor: nil}} =
             Workflow.history(scope, subject, limit: 1, after: cursor)

    assert second.id > first.id and second.status == first.status and second.comment == "A note"
    assert_raise ArgumentError, fn -> Workflow.history(scope, subject, limit: 0) end
  end

  test "seed preserves operational configuration and uses stable keys", %{
    scope: scope,
    subject: subject
  } do
    SQL.query!(
      Repo,
      "UPDATE base_workflow_status_transitions SET is_active = false WHERE to_code = 'closed'",
      []
    )

    assert {:ok, :seeded} = Workflow.seed_definitions()
    assert {:error, :invalid_edge} = Workflow.transition(scope, subject, "closed")

    assert Enum.find(Repo.all(EdgeSchema), &(&1.to_code == "review")).guard_class ==
             "example.guard"

    assert {:ok, transitions} = Workflow.available_transitions(scope, subject)
    assert Enum.map(transitions, & &1.to) == ["review"]
  end

  test "conflicting binding cannot be rebound", %{scope: scope, subject: subject} do
    SQL.query!(
      Repo,
      """
      INSERT INTO base_workflow_subject_bindings (tenant_id, flow, flow_id, subject_type, subject_id, owner, created_at)
      VALUES (2, 'example_flow', $1, 'example.record', $2, 'domain/example', now())
      """,
      [subject.id, to_string(subject.id)]
    )

    assert {:error, :subject_binding_conflict} = Workflow.adopt_subject(scope, subject)
    assert {:error, :subject_binding_conflict} = Workflow.transition(scope, subject, "closed")
    assert state(subject.id).status == "draft"
    assert {:ok, %{entries: []}} = Workflow.history(scope, subject)
  end

  test "transition tat skips recorded comments but not legacy facts", %{
    scope: scope,
    subject: subject
  } do
    assert {:ok, initial} = Workflow.record_initial(scope, subject)

    SQL.query!(
      Repo,
      "UPDATE base_workflow_status_history SET transitioned_at = transitioned_at - interval '1 hour' WHERE id = $1",
      [initial.id]
    )

    assert {:ok, comment} = Workflow.record_comment(scope, subject, %{comment: "A note"})
    assert is_nil(comment.tat)
    assert {:ok, %{history: history}} = Workflow.transition(scope, subject, "review")
    assert history.tat >= 3600

    other = subject!()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    SQL.query!(
      Repo,
      """
      INSERT INTO base_workflow_status_history (flow, flow_id, status, metadata, transitioned_at)
      VALUES ('example_flow', $1, 'draft', '{"note":true}', $2),
             ('example_flow', $1, 'draft', NULL, $3)
      """,
      [other.id, NaiveDateTime.add(now, -3600), now]
    )

    assert {:ok, _} = Workflow.adopt_subject(scope, other)
    assert {:ok, %{history: legacy}} = Workflow.transition(scope, other, "review")
    assert legacy.tat < 3600
  end

  test "an inactive current status lists no transitions", %{scope: scope, subject: subject} do
    SQL.query!(
      Repo,
      "UPDATE base_workflow_status_configs SET is_active = false WHERE code = 'draft'",
      []
    )

    assert {:ok, []} = Workflow.available_transitions(scope, subject)
    assert {:error, :invalid_edge} = Workflow.transition(scope, subject, "closed")
  end

  test "a subject bound under another flow refuses instead of raising", %{
    scope: scope,
    subject: subject
  } do
    SQL.query!(
      Repo,
      """
      INSERT INTO base_workflow_subject_bindings (tenant_id, flow, flow_id, subject_type, subject_id, owner, created_at)
      VALUES (1, 'earlier_flow', $1, 'example.record', $2, 'domain/example', now())
      """,
      [subject.id, to_string(subject.id)]
    )

    assert {:error, :subject_binding_conflict} = Workflow.adopt_subject(scope, subject)
    assert {:error, :subject_binding_conflict} = Workflow.transition(scope, subject, "closed")
    assert state(subject.id).status == "draft"
    assert Repo.all(HistorySchema) == []
  end

  test "impersonation remains attributed", %{system: system, subject: subject} do
    scope =
      Authentication.sign_in(system, 7, 10,
        impersonator_id: 9,
        impersonation_session_id: "session"
      )

    assert {:ok, _} = Workflow.transition(scope, subject, "closed")
    assert {:ok, %{entries: [entry]}} = Workflow.history(scope, subject)
    assert entry.metadata["_workflow"]["impersonator_id"] == 9

    assert SQL.query!(Repo, "SELECT actor_id, impersonator_id FROM base_audit_actions", []).rows ==
             [[7, 9]]
  end
end
