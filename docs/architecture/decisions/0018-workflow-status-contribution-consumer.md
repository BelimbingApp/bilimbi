# ADR 0018: Workflow status definitions and owner adapters

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Status kernel, durable coordination, ownership and source-data adoption
**Last Updated:** 2026-10-03

## Context

Belimbing persists global flow/configuration/edge/kanban rows and status history
without a tenant column. Runtime subject, guard and action identities include
PHP class strings. Bilimbi must retain those rows while enforcing tenant and
actor authority without Base reading optional owners' private relations.

## Decision

`:workflow` is a peer consumer in the descriptor-owned contribution snapshot.
Base Workflow validates immutable plain maps for subjects, guards, actions, flow defaults and versioned processes. Adapter modules must implement the corresponding public behaviour
and belong to the contributing OTP application. Owners declare `base/workflow`.
Stable keys and exact legacy aliases are unique; a flow's subject and hooks
belong to its owner. Aliases are data, never executable class names.

Contribution defaults initialize missing rows only through an explicit owner
production seed callback. Existing configuration remains authoritative, including
inactive rows. Startup, schema verification and ledger adoption never seed,
rewrite history, change status or translate legacy strings.

The status kernel owns the five compatible status/configuration tables. A
separate Bilimbi-only subject-binding relation assigns each historical
(flow, flow_id) to exactly one proven tenant, stable subject and owner. Its
absence is valid during baseline adoption; a partially present relation fails
verification. Owner adoption callbacks lock and prove real subjects. No inferred
backfill runs. Unbound history remains preserved and unavailable to tenant reads.

Each transition locks and rereads the owner subject on the shared Repo, repeats
owner policy and Authz checks, validates the persisted active edge and registered
hooks, and commits owner persistence, owner database action, history and semantic
Audit fact in one transaction. The sealed Scope actor supplies attribution,
including impersonation. Arbitrary actor/tenant context is refused. Hook failures
roll back all effects. Owners retain responsibility for business rules and locks.

Durable coordination owns compatible definition-version, run, work, dependency,
event and transition-outbox tables. A process contribution binds its registered
subject and descriptor-owned `ProcessAdapter`; the owner proves company and
current round/attempt authority. Start materializes one graph, binds an immutable
fingerprint, and preserves legacy namespaced idempotency keys. Reconciliation
uses the existing graph. Subject -> run -> ordered item locking serializes
parallel completions and per-run event allocation. All state, owner database
effects, events and semantic Audit facts commit in the shared Repo transaction.

Verification/adoption retains in-flight and paused states, work versions, leases,
JSON, timestamps and sequences without executing owner code. Unknown owners,
unresolved scope and unavailable version/fingerprint contracts stay retained and
fail execution. Supersede uses the source `blocked` state plus its event. A bounded
scoped worklist rechecks owner policy and exposes no sibling-private relations.

## Consequences

- Base gains no dependency on Core, Domain or Extension implementations.
- Legacy class strings remain intact; private owner extensions contribute their
  mappings. Unknown mappings fail at runtime without invalidating preserved data.
- Bounded scoped history retains initial entries, comments, inactive codes and
  nullable or agent actor identities with deterministic timestamp/id cursors.
- Human actions and external dispatch remain later slices. The coordinator
  resumes supported durable runs; pending legacy outbox rows remain retained
  without delivery in this slice.
- The public API and contribution shape are documented in
  `apps/base/workflow/docs/README.md`; validation owns the executable contract.
