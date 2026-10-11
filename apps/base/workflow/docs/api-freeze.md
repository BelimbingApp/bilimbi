# Workflow API freeze for initial consumers

This note freezes the consumer-facing contracts exercised by the reference
flow. The implementation remains private to `base/workflow`; consumer modules
must not import its schemas, queries, or coordination internals.

## Stable entry points

- Status: `transition/4`, `available_transitions/2`, `record_initial/3`,
  `record_comment/3`, and `history/3`.
- Durable work: `start_run/4`, `get_run/2`, `complete_work/4`,
  `supersede_run/3`, and bounded `pending_work/2`.
- Human actions: `available_actions/2` and `execute_action/3`.
- Maintenance: `reconcile_running_runs/1` and `deliver_transition_events/1`,
  installation-wide and run by the contributed maintenance schedule.

Tenant-owned calls take a validated `Bilimbi.Base.Tenancy.Scope` and a stable
subject reference `%{type: key, id: id}`. Return values are plain maps, never
Ecto schemas. See `README.md` for the full argument, cursor, refusal, and
transaction contracts.

## Extension seam

Owners contribute immutable plain data under `:workflow`: subjects, flows,
guards, actions, versioned process definitions, human actions, and transition
listeners. Adapters
must be compiled modules owned by the contributing descriptor and implement
the matching Workflow behaviour. A subject adapter proves and scopes owner
records; process adapters authorize durable coordination; human handlers make
database changes inside the Workflow transaction. External effects belong in
a `TransitionListener`, delivered at least once after commit from the durable
outbox; its event map is part of this freeze.

## Compatibility commitments

Existing status/history and coordination rows are verified and adopted in
place. Adoption does not rewrite legacy identities, synthesize a new run, seed
definitions, or infer unresolved tenant ownership. New consumers must retain
old definition versions while saved runs depend on them and keep their stable
subject aliases installed while retained history or requests need them.

## Changes requiring review

Changing function names or arities, subject-reference identity, public fact
keys, cursor ordering, idempotency semantics, transaction boundaries, or
adoption behavior requires an explicit compatibility review and an update to
this note. New consumer-specific workbench or business policy remains owned by
that consumer and does not expand the Base Workflow API implicitly.
