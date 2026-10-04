defmodule Bilimbi.Base.Workflow.HumanActionTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.{Authentication, ForgedActorError}

  alias Bilimbi.Base.Workflow.{
    IntentDigest,
    LegacyHumanActionFixture,
    RequestSchema,
    TestSubjectSchema,
    WorkSchema
  }

  alias Ecto.Adapters.SQL
  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    create_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    system = TenancyFixtures.scope()
    scope = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(system, 10, :user, 7, "admin.test.record.view", true)

    %{scope: scope, subject: subject!(), system: system}
  end

  test "availability lists permitted actions and due work with the tokens a page echoes back",
       c do
    assert {:ok, %{subject_version: version, actions: [approve]}} =
             Workflow.available_actions(c.scope, c.subject)

    assert is_binary(version) and byte_size(version) == 64
    assert %{key: "example.approve", label: "Approve", executor_key: nil} = approve
    assert %{process_run_id: nil, work_item_id: nil, work_version: nil} = approve
    refute Map.has_key?(approve, :handler)
    run = start!(c)

    assert {:ok, %{subject_version: ^version, actions: [^approve, first]}} =
             Workflow.available_actions(c.scope, c.subject)

    assert %{key: "example.first", executor_key: "example.first", work_version: 1} = first
    assert first.process_run_id == run.id and first.work_item_id == item_id(run, "first")

    future = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(60)

    Repo.update_all(from(w in WorkSchema, where: w.id == ^first.work_item_id),
      set: [available_at: future]
    )

    assert {:ok, %{actions: [^approve]}} = Workflow.available_actions(c.scope, c.subject)
    unprivileged = Authentication.sign_in(c.system, 9, 10)

    assert {:ok, %{subject_version: ^version, actions: []}} =
             Workflow.available_actions(unprivileged, c.subject)

    assert {:error, :human_actor_required} = Workflow.available_actions(c.system, c.subject)
    foreign = Authentication.sign_in(TenancyFixtures.scope(2), 7, 10)
    assert {:error, :subject_not_found} = Workflow.available_actions(foreign, c.subject)

    assert {:error, :owner_refused} =
             Workflow.available_actions(c.scope, subject!(%{marker: "private"}))
  end

  test "availability includes work beyond the first candidate page", c do
    process = Bilimbi.Base.Workflow.TestProcessContributions.parallel()

    steps =
      for index <- 1..501 do
        %{key: "step-#{index}", label: "Step #{index}", executor_key: "example.first"}
      end

    install_registry!([%{process | steps: steps}])
    run = start!(c)

    assert {:ok, %{work_items: items}} = Workflow.get_run(c.scope, run.id)
    assert {:ok, %{actions: [approve | actions]}} = Workflow.available_actions(c.scope, c.subject)
    assert approve.key == "example.approve"
    assert length(actions) == 501
    assert Enum.map(actions, & &1.work_item_id) == Enum.sort(Enum.map(items, & &1.id))
    assert Enum.all?(actions, &(&1.key == "example.first" and &1.process_run_id == run.id))
  end

  test "a non-work action commits the handler effect, the request and the audit fact together",
       c do
    assert {:ok, %{subject_version: version}} = Workflow.available_actions(c.scope, c.subject)
    payload = %{"comment" => "Looks good / ok", "tags" => ["b", "a"]}
    request = approve("approve:1", version, payload)
    assert {:ok, result} = Workflow.execute_action(c.scope, c.subject, request)

    assert %{action_key: "example.approve", outcome: "completed", replayed: false} = result
    assert %{work_item_id: nil, process_run_id: nil} = result
    assert result.result_ref == "owner-result:#{c.subject.id}"
    assert result.output == %{"handled" => "example.approve", "payload" => payload}
    assert state(c.subject.id).marker == "human:example.approve"

    assert [row] = Repo.all(RequestSchema)
    assert row.id == result.request_id and row.tenant_id == 1
    assert row.actor_type == "user" and row.actor_id == 7
    assert row.subject_type == "example.record" and row.subject_id == to_string(c.subject.id)
    assert row.idempotency_key == "approve:1" and not is_nil(row.completed_at)

    assert {:ok, row.intent_hash} ==
             IntentDigest.digest(%{
               subject_type: "example.record",
               subject_id: to_string(c.subject.id),
               actor_type: "user",
               actor_id: 7,
               action_key: "example.approve",
               process_run_id: nil,
               work_item_id: nil,
               payload: payload
             })

    assert row.result == %{
             "action_key" => "example.approve",
             "outcome" => "completed",
             "output" => result.output,
             "result_ref" => result.result_ref,
             "work_item_id" => nil
           }

    assert [["user", 7, 1, audit]] =
             SQL.query!(
               Repo,
               "SELECT actor_type, actor_id, tenant_id, payload FROM base_audit_actions WHERE event = 'workflow.human_action.completed'",
               []
             ).rows

    assert audit["request_id"] == row.id and audit["action_key"] == "example.approve"
    assert audit["subject_type"] == "example.record"
  end

  test "a work-bound action completes its work item with the handler outcome in one transaction",
       c do
    run = start!(c)
    {version, first} = first_action(c)
    request = first_request("first:1", version, first, %{"score" => "9"})
    assert {:ok, result} = Workflow.execute_action(c.scope, c.subject, request)
    assert result.work_item_id == first.work_item_id and result.process_run_id == run.id

    assert {:ok, %{run: %{status: "running"}, work_items: [item | rest]}} =
             Workflow.get_run(c.scope, run.id)

    assert %{status: "completed", version: 2, outcome: "completed"} = item
    assert item.output == result.output and item.result_ref == result.result_ref
    assert Enum.all?(rest, &(&1.status == "available"))
    assert [completed] = Enum.filter(events!(c.scope, run.id), &(&1.type == "work.completed"))
    assert completed.work_item_id == first.work_item_id

    assert %{"source" => "human_action", "action_key" => "example.first"} = completed.payload
    assert %{"actor_type" => "user", "actor_id" => 7} = completed.payload
    assert completed.payload["request_id"] == result.request_id
    assert completed.payload["output"] == result.output
    assert state(c.subject.id).marker == "human:example.first"

    assert {:ok, %{actions: [%{key: "example.approve"}]}} =
             Workflow.available_actions(c.scope, c.subject)

    assert {:ok, %{entries: pending}} = Workflow.pending_work(c.scope)
    assert Enum.map(pending, & &1.step_key) == ~w(second third)
  end

  test "a stale page refuses before any effect", c do
    run = start!(c)
    {version, first} = first_action(c)
    request = first_request("first:stale", version, first, %{})

    assert {:error, :stale_subject} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | expected_subject_version: "stale"
             })

    assert {:error, :stale_work} =
             Workflow.execute_action(c.scope, c.subject, %{request | expected_work_version: 2})

    assert {:error, :work_not_found} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | work_item_id: first.work_item_id + 1000
             })

    assert {:error, :executor_mismatch} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | work_item_id: item_id(run, "second")
             })

    other = subject!()

    assert {:ok, other_run} =
             Workflow.start_run(c.scope, "example.parallel", other, idempotency_key: "other")

    assert {:error, :process_subject_mismatch} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | process_run_id: other_run.id,
                 work_item_id: item_id(other_run, "first")
             })

    assert {:error, :run_not_found} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | process_run_id: other_run.id + 1000
             })

    Repo.update_all(from(s in TestSubjectSchema, where: s.id == ^c.subject.id),
      set: [marker: "edited"]
    )

    assert {:error, :stale_subject} = Workflow.execute_action(c.scope, c.subject, request)
    assert state(c.subject.id).marker == "edited"
    assert Repo.all(RequestSchema) == []
    assert Repo.get!(WorkSchema, first.work_item_id).version == 1
    assert length(events!(c.scope, run.id)) == 10
    assert audit_count() == 0
  end

  test "a repeated request returns the saved outcome without repeating any effect", c do
    run = start!(c)
    {version, first} = first_action(c)
    request = first_request("first:1", version, first, %{"score" => "9"})
    assert {:ok, result} = Workflow.execute_action(c.scope, c.subject, request)

    Repo.update_all(from(s in TestSubjectSchema, where: s.id == ^c.subject.id),
      set: [marker: "reset"]
    )

    events = events!(c.scope, run.id)

    # The first execution changed the subject, so the echoed versions are now
    # stale; a replay still answers before any version check.
    assert {:ok, replay} = Workflow.execute_action(c.scope, c.subject, request)
    assert replay == %{result | replayed: true}

    assert {:ok, %{replayed: true}} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | expected_subject_version: "anything",
                 expected_work_version: 99
             })

    assert state(c.subject.id).marker == "reset"
    assert events!(c.scope, run.id) == events
    assert Repo.aggregate(RequestSchema, :count) == 1
    assert Repo.get!(WorkSchema, first.work_item_id).version == 2
    assert audit_count() == 1

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(c.scope, c.subject, %{request | payload: %{"score" => "8"}})

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(
               c.scope,
               c.subject,
               approve("first:1", version, %{"score" => "9"})
             )

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(
               c.scope,
               subject!(),
               approve("first:1", version, %{"score" => "9"})
             )

    colleague = Authentication.sign_in(c.system, 9, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               c.system,
               10,
               :user,
               9,
               "admin.test.record.view",
               true
             )

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(colleague, c.subject, request)

    assert Repo.aggregate(RequestSchema, :count) == 1
    assert state(c.subject.id).marker == "reset"
  end

  test "another tenant, a missing capability, a system actor and a forged actor refuse", c do
    assert {:ok, %{subject_version: version}} = Workflow.available_actions(c.scope, c.subject)
    request = approve("refused", version, %{})
    foreign = Authentication.sign_in(TenancyFixtures.scope(2), 7, 10)
    assert {:error, :subject_not_found} = Workflow.execute_action(foreign, c.subject, request)
    unprivileged = Authentication.sign_in(c.system, 9, 10)

    assert {:error, :missing_capability} =
             Workflow.execute_action(unprivileged, c.subject, request)

    assert {:error, :missing_capability} =
             Workflow.execute_action(c.scope, c.subject, %{
               request
               | action_key: "example.restricted"
             })

    assert {:error, :human_actor_required} = Workflow.execute_action(c.system, c.subject, request)

    assert_raise ForgedActorError, fn ->
      Workflow.execute_action(
        %{c.scope | actor: %{c.scope.actor | user_id: 9}},
        c.subject,
        request
      )
    end

    private = subject!(%{marker: "private"})
    assert {:error, :owner_refused} = Workflow.execute_action(c.scope, private, request)
    assert state(c.subject.id).marker == "original" and state(private.id).marker == "private"
    assert Repo.all(RequestSchema) == []
    assert audit_count() == 0
  end

  test "a refused or invalid handler outcome rolls back the request and the work", c do
    run = start!(c)
    {version, first} = first_action(c)

    for payload <- [%{"refuse" => true}, %{"bad_outcome" => true}] do
      reason = if payload["refuse"], do: :handler_refused, else: :invalid_handler_outcome

      assert {:error, ^reason} =
               Workflow.execute_action(
                 c.scope,
                 c.subject,
                 first_request("first:#{reason}", version, first, payload)
               )

      assert {:error, ^reason} =
               Workflow.execute_action(
                 c.scope,
                 c.subject,
                 approve("approve:#{reason}", version, payload)
               )
    end

    assert {:error, :business_refused} =
             Repo.transact(fn ->
               assert {:ok, _} =
                        Workflow.execute_action(
                          c.scope,
                          c.subject,
                          approve("approve:ok", version, %{})
                        )

               {:error, :business_refused}
             end)

    assert state(c.subject.id).marker == "original"
    assert Repo.all(RequestSchema) == []
    assert Repo.get!(WorkSchema, first.work_item_id).status == "available"
    assert length(events!(c.scope, run.id)) == 10
    assert audit_count() == 0
  end

  test "a retained source request replays by its alias and digest without executing", c do
    subject = subject!(%{id: 41})
    schema = Bilimbi.Base.Database.DataCase.temporary_schema!()

    payload = %{
      "comment" => "Looks good / ok",
      "score" => "9.5",
      "tags" => ["b", "a"],
      "unicode" => "ü 😀 \u2028x",
      "nested" => %{"z" => true, "a" => %{"empty" => %{}}},
      "quote" => "He said \"hi\"\n\t<>&'\\",
      "flag" => false,
      "none" => nil,
      "count" => 3
    }

    # The digest PHP computed for this payload under the source class name.
    id =
      LegacyHumanActionFixture.insert_request!(Repo, schema, %{
        idempotency_key: "legacy-approve",
        intent_hash: "601c9e0560436bce8e6617470a2aaf636db0017a2866be1a0b4aa8723003bbdc",
        action_key: "example.approve",
        output: %{"legacy_fact" => 1},
        result_ref: "legacy-result:1"
      })

    assert {:ok, %{subject_version: version}} = Workflow.available_actions(c.scope, subject)
    request = approve("legacy-approve", version, payload)

    assert {:ok,
            %{
              request_id: ^id,
              action_key: "example.approve",
              outcome: "completed",
              output: %{"legacy_fact" => 1},
              result_ref: "legacy-result:1",
              work_item_id: nil,
              replayed: true
            }} = Workflow.execute_action(c.scope, subject, request)

    assert state(41).marker == "original" and audit_count() == 0
    assert Repo.get!(RequestSchema, id).subject_type == "Legacy\\Example\\Record"

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(c.scope, subject, %{
               request
               | payload: Map.put(payload, "count", 4)
             })

    {:ok, open_hash} =
      IntentDigest.digest(%{
        subject_type: "Legacy\\Example\\Record",
        subject_id: "41",
        actor_type: "user",
        actor_id: 7,
        action_key: "example.approve",
        process_run_id: nil,
        work_item_id: nil,
        payload: %{"open" => true}
      })

    LegacyHumanActionFixture.insert_request!(Repo, schema, %{
      idempotency_key: "legacy-open",
      intent_hash: open_hash,
      action_key: "example.approve",
      result: nil,
      completed_at: nil
    })

    assert {:error, :request_incomplete} =
             Workflow.execute_action(
               c.scope,
               subject,
               approve("legacy-open", version, %{"open" => true})
             )

    LegacyHumanActionFixture.insert_request!(Repo, schema, %{
      idempotency_key: "legacy-unknown",
      intent_hash: String.duplicate("d", 64),
      subject_type: "Unknown\\Retired\\Record",
      action_key: "example.approve"
    })

    assert {:error, :idempotency_conflict} =
             Workflow.execute_action(c.scope, subject, approve("legacy-unknown", version, %{}))

    # A source digest over a payload this codec cannot reproduce is never
    # treated as unseen: the request refuses before any write.
    assert {:error, :unreproducible_intent} =
             Workflow.execute_action(
               c.scope,
               subject,
               approve("legacy-approve", version, %{"score" => 9.5})
             )

    assert Repo.aggregate(RequestSchema, :count) == 3
    assert state(41).marker == "original"
  end

  test "request shape, work binding and unknown actions fail closed", c do
    assert {:ok, %{subject_version: version}} = Workflow.available_actions(c.scope, c.subject)
    base = approve("shape", version, %{})

    missing_fields =
      Enum.map([:action_key, :idempotency_key, :expected_subject_version], &Map.delete(base, &1))

    for request <- [%{} | missing_fields] do
      assert {:error, :invalid_request} = Workflow.execute_action(c.scope, c.subject, request)
    end

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, Map.put(base, :actor_id, 7))

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, %{base | idempotency_key: " "})

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, %{base | payload: "scalar"})

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, %{base | expected_subject_version: ""})

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, Map.put(base, :process_run_id, 1))

    assert {:error, :invalid_request} =
             Workflow.execute_action(c.scope, c.subject, Map.put(base, :work_item_id, 0))

    assert {:error, :invalid_request} = Workflow.execute_action(c.scope, c.subject, [])

    assert {:error, :work_binding_required} =
             Workflow.execute_action(c.scope, c.subject, %{base | action_key: "example.first"})

    assert {:error, :action_unavailable} =
             Workflow.execute_action(c.scope, c.subject, %{base | action_key: "example.unknown"})

    assert {:error, :unknown_subject} =
             Workflow.execute_action(c.scope, %{type: "other.record", id: 1}, base)

    assert {:error, :unreproducible_intent} =
             Workflow.execute_action(c.scope, c.subject, %{base | payload: %{"ratio" => 0.5}})

    assert {:error, :unreproducible_intent} =
             Workflow.execute_action(c.scope, c.subject, %{base | payload: %{"12" => "x"}})

    assert Repo.all(RequestSchema) == [] and state(c.subject.id).marker == "original"
  end

  defp approve(key, version, payload),
    do: %{
      action_key: "example.approve",
      idempotency_key: key,
      expected_subject_version: version,
      payload: payload
    }

  defp first_request(key, version, first, payload) do
    %{
      action_key: "example.first",
      idempotency_key: key,
      expected_subject_version: version,
      payload: payload,
      process_run_id: first.process_run_id,
      work_item_id: first.work_item_id,
      expected_work_version: first.work_version
    }
  end

  defp first_action(c) do
    assert {:ok, %{subject_version: version, actions: actions}} =
             Workflow.available_actions(c.scope, c.subject)

    {version, Enum.find(actions, &(&1.key == "example.first"))}
  end

  defp start!(c) do
    assert {:ok, run} =
             Workflow.start_run(c.scope, "example.parallel", c.subject,
               idempotency_key: "attempt:1"
             )

    run
  end

  defp item_id(run, step),
    do:
      Repo.one!(
        from(w in WorkSchema,
          where: w.process_run_id == ^run.id and w.step_key == ^step,
          select: w.id
        )
      )

  defp events!(scope, id) do
    assert {:ok, %{entries: events}} = Workflow.run_events(scope, id, limit: 500)
    events
  end

  defp audit_count do
    [[count]] =
      SQL.query!(
        Repo,
        "SELECT count(*) FROM base_audit_actions WHERE event = 'workflow.human_action.completed'",
        []
      ).rows

    count
  end
end
