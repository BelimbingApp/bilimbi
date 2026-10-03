# Base Workflow status kernel

Workflow owns status configuration and history. Its public facade accepts a
`Bilimbi.Base.Tenancy.Scope` and `%{type: "owner.record", id: 42}`. It never
queries an owner's subject table. UI, durable coordination, human actions and
outbox dispatch are outside this slice.

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
The other source Workflow tables are untouched and remain for later slices.

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
