# Base Workflow

Workflow owns status configuration and history. Its public facade accepts a
`Bilimbi.Base.Tenancy.Scope` and `%{type: "owner.record", id: 42}`. It never
queries an owner's subject table. The status kernel and durable coordinator share
this boundary. UI, human-action routing and external/outbox dispatch are later slices.

An owner declares `base/workflow` and contributes immutable defaults:

```elixir
%{workflow: %{
  subjects: [%{key: "owner.record", adapter: Owner.WorkflowSubject,
    aliases: ["Legacy\\Owner\\Record"]}],
  guards: [%{key: "owner.ready", adapter: Owner.ReadyGuard,
    aliases: ["Legacy\\Owner\\ReadyGuard"]}],
  actions: [%{key: "owner.submitted", adapter: Owner.SubmitAction}],
  flows: [%{code: "owner_flow", subject: "owner.record", label: "Review",
    statuses: [%{code: "draft", label: "Draft"}, %{code: "review", label: "Review"}],
    transitions: [%{from: "draft", to: "review", capability: "owner.record.submit",
      guard: "owner.ready", action: "owner.submitted"}]}]
}}
```

`ContributionValidator` requires descriptor provenance, compiled adapter
ownership, behaviour callbacks, unique public keys/aliases and valid graph
references. Contributions perform no I/O. Definitions contain optional labels,
positions, activity flags, JSON context, SLA and kanban defaults; the validator
is the exact field authority. Actual customer mappings belong in private owners.

`SubjectAdapter.load/3` begins with `Tenancy.scope_query/2` and locks/rereads the
subject with `FOR UPDATE` for `:lock`. It returns `Workflow.Subject` containing
only proven identity, tenant/company, current status and plain owner facts.
`authorize/3` enforces owner policy for every operation, including null-capability
edges and adoption. `persist/4` writes the proven status on the shared Repo.
Guards and actions perform database work within that same transaction; external
effects need the later durable-dispatch slice.

Call `transition(scope, ref, "review", %{comment: "Ready", input: %{}})`.
Allowed context keys are `:comment`, `:comment_tag`, `:assignees`, `:attachments`,
`:metadata` and `:input`. Metadata uses string keys and reserves `_workflow` for
sealed actor/subject attribution. Tenant/actor claims are rejected. All refusal
results roll back status, hook effects, bindings, history and the semantic Audit
fact. Owner policy must separately refuse system principals on human approvals.

`available_transitions/2` lists active edges between active statuses whose
capability and adapters are available. Context-dependent guards run only during execution; availability is
not authorization to perform a transition. `record_initial/3` refuses existing
history; `record_comment/3` appends a same-status fact without a state change.
A transition fact's `tat` is the whole seconds since the subject's latest earlier
history fact, skipping only facts whose `_workflow.kind` provenance is
`record_comment`. Legacy facts carry no such provenance and always count, so a
legacy same-status note restarts the measure. `tat` is `nil` on the first
transition without earlier history and on `record_initial/3` or
`record_comment/3` facts.
`history/3` returns `%{entries: facts, next_cursor: cursor}`, ordered oldest first
by timestamp then id. Pass `after: cursor` and `limit: 1..500` (default 50).
Historical nullable actors, agent IDs, JSON arrays and inactive status codes are
returned unchanged, without treating them as authenticated users.

Fresh databases use umbrella-root `mix bilimbi.migrate`. Existing databases use
`mix bilimbi.schema.verify`, then `mix bilimbi.schema.adopt`, then
`mix bilimbi.migrate` for the pending subject-binding addition. Verification
checks exact types, indexes, constraints, sequence ownership/state and triggers.
The compatible baseline includes kanban rows even though no UI ships here.
The coordination baseline also owns the six compatible process/outbox tables;
source outbox rows are preserved, with dispatch deferred to its delivery slice.

After migration, an installed owner calls `adopt_subject/2` under its explicit
adoption policy. This locks/proves the subject and binds existing history without
rewriting it, including inactive flows; conflicting scope/identity fails. Missing subjects and unknown
aliases stay preserved and unreadable rather than receiving guessed ownership.
Adoption neither seeds definitions nor interprets legacy PHP values as modules.

`seed_definitions/0` is the explicit insert-only initializer for owner production
seed callbacks. Call it after installing the contribution snapshot. Existing
operator configuration always wins, including inactive flags and legacy aliases.
New identities use stable public keys; no business flow is hard-coded in Base.

The architectural ownership decision is [ADR 0018](../../../../docs/architecture/decisions/0018-workflow-status-contribution-consumer.md).


## Durable coordination

An owner contributes versioned process definitions under `workflow.processes`:

```elixir
%{key: "owner.review", version: 1, subject: "owner.record",
  adapter: Owner.ProcessPolicy,
  steps: [
    %{key: "first", label: "First review", executor_key: "owner.first"},
    %{key: "second", label: "Second review", executor_key: "owner.second"},
    %{key: "finish", label: "Finish",
      dependencies: [%{step_key: "first"}, %{step_key: "second"}]}]}
```

The validator proves descriptor/adapter ownership and subject ownership, checks
positive versions and acyclic dependencies, and fixes the complete executable
contract's fingerprint. A persisted key/version is immutable: change the version
when changing any step contract. Old executable versions stay installed while
in-flight runs need them. Definitions are plain terms with no I/O and are saved
insert-only when an authorized owner starts a run; boot never starts runs.

`ProcessAdapter.authorize/4` receives the locked subject and plain run facts for
`:start`, `:read`, `:complete`, `:supersede`, `:reconcile`, `:signal`, `:pause`,
`:resume`, `:claim`, `:heartbeat`, `:fail`, `:block_claim`, `:waive` and `:block`;
leaseholder completion is `:complete`. A new start
has no saved ID; replay repeats `:start` with the saved ID and input. Both the
subject and process adapters must enforce access. The owner enforces capabilities,
company eligibility, and current round/attempt binding, using its own public
boundary; Workflow does not query those relations. `:read` does not authorize
completion. Owners perform business writes and `complete_work/4` in one shared
Repo transaction so a later refusal rolls back owner and Workflow effects.

Start with `start_run(scope, "owner.review", ref, idempotency_key: "attempt:2",
input: %{"carried_fact_ids" => %{}})`. `:version` selects an installed version;
omission selects the highest. Other options are `:correlation_key`, `:priority`
and a UTC `NaiveDateTime` in whole seconds for `:available_at`. Start keys use the
legacy tenant/definition namespace and long-key SHA-256 shortening. Repeating a
start preserves the run and work IDs; changed input, subject or definition
conflicts. Legacy subject aliases and saved payloads remain intact.

`get_run/2` returns `%{run: facts, work_items: facts}` after owner proof and exact
saved graph/fingerprint checks. Reads (`get_run/2`, `run_events/3` and
`pending_work/2`) take no row locks. Its size is bounded by the installed definition,
not a growing run list. Complete an available, due item by ID or `%{step_key: key}`:

```elixir
complete_work(scope, run_id, %{step_key: "first"}, %{
  expected_version: 1, executor_key: "owner.first", outcome: "completed",
  output: %{"fact_id" => 42}, result_ref: "owner-result:42"
})
```

Completion checks the current run, work version, executor and due time under the
subject/run/item locks. Events allocate consecutive per-run sequences in the
same transaction and carry sealed Audit attribution. Parallel independent work
becomes available together. Dependencies default to `"all"` and acceptable outcome
`["completed"]`; `"any"` releases after one accepted outcome. Rejected terminal
prerequisites block work when no acceptable outcome remains. Signal gates use
`:required_signal`; `signal_run/5` records an idempotent owner fact. Reusing its
key with changed content conflicts. `:delay_seconds` starts a persisted timer
once dependencies and any signal are satisfied.

`reconcile_run/2` repairs expired leases, fences stale completions by incrementing
the saved version, and releases satisfied dependencies/timers. It operates on the
same saved graph after process/Repo restart. Final-attempt expiry fails work;
remaining attempts return it to pending. Live leases remain untouched. A retained
run marked by Belimbing as `Process definition cannot be reconciled: ...` has
the mark cleared, with `process.definition_restored`, once its installed
definition is proved again.
`supersede_run/3` requires a reason and refuses live leases. It preserves completed
facts, blocks unfinished work, aggregates the terminal run state, and appends
`process.superseded`. Supersede's durable state is `"blocked"`; there is no new
`"superseded"` status.

`pause_run/3` pauses a running run with a reason and appends `process.paused`;
a paused run releases no work until resumed. Signals and `complete_work/4` are
refused, while a live lease may still finish its item.
`resume_run/2` clears the pause, appends `process.resumed` and reconciles the
saved graph, so an adopted paused run continues with its original items.

Workers lease due work with `claim_work(scope, "worker-1", lease_seconds: 300)`,
optionally filtered by `:definition_key`, `:executor_keys` or `:run_ids`. Due
pending work and expired leases are reconciled before the lease is taken. Only
runs of an installed definition version and fingerprint are candidates, and a
run refused under its lock is skipped, so retained unsupported runs never starve
supported work. The
result's `claim: %{run_id, work_item_id, lease_token}` is required by
`heartbeat_work/3`, `complete_claimed_work/3`, `fail_work/4` and
`block_claimed_work/4`; a mismatched or expired token is refused, and a repeated
call on a terminal item returns it unchanged. Adopted leases keep their saved
tokens, so a worker holding one completes it through the same calls.
`fail_work/4` returns retryable work with attempts remaining to pending at
`:retry_at` (the caller's backoff; default now) and records `work.retry_scheduled`;
otherwise the item fails. `waive_work/5` and `block_work/4` are the owner or
operator path for unfinished work and need a reason.

`pending_work/2` returns `%{entries: facts, next_cursor: cursor}`. Pass `:after`,
`:limit` (1..500, default 50), and optional `:subject`, `:run_id`, `:definition_key`
or `:executor_keys`. Candidates must be tenant-scoped, running and due, with due
available work and no run error. Owner proof and current state are repeated before
returning facts; lease ownership/tokens are hidden. Ordering is work priority
descending, availability then ID. The cursor advances over scanned candidates,
including owner-policy exclusions, so a page can be empty with a next cursor.
This bounded worklist supplies no relational owner-workbench count.
`run_events/3` provides bounded event pages ordered by saved run sequence.

Verify-then-adopt preserves all compatible run/work states, definition rows,
leases, dependency edges, events, JSON shapes, timestamps and sequences. It
rejects structural drift or contradictory graph tenant identity, without guessing
an unresolved run's tenant or translating its owner. Unknown/retired definitions,
aliases, fingerprints and unresolved runs stay preserved and fail execution;
they are never replaced by a fresh run. `:legacy_v1` fingerprints
match ordered PHP v1 JSON for supported values, including empty lists, sorted
objects and Unicode separators. Floating values fail explicitly because PHP's
number serialization differs. Numeric object keys also refuse explicitly because
PHP arrays coerce/sort them and can become lists; express those as lists.
`:legacy_v1` is the only fingerprint format. Compatible owner mappings belong in private
extensions, not the public platform.

`base_workflow_human_action_requests` belongs to slice 3, the human action
gate. This baseline neither creates nor reads it; adopting a database that has
it leaves its rows untouched.
