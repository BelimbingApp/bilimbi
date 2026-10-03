# ADR 0018: Workflow status definitions and owner adapters

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Status kernel, ownership and source-data adoption
**Last Updated:** 2026-10-03

## Context

Belimbing persists global flow/configuration/edge/kanban rows and status history
without a tenant column. Runtime subject, guard and action identities include
PHP class strings. Bilimbi must retain those rows while enforcing tenant and
actor authority without Base reading optional owners' private relations.

## Decision

`:workflow` is a peer consumer in the descriptor-owned contribution snapshot.
Base Workflow validates immutable plain maps for subjects, guards, actions and
flow defaults. Adapter modules must implement the corresponding public behaviour
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

## Consequences

- Base gains no dependency on Core, Domain or Extension implementations.
- Legacy class strings remain intact; private owner extensions contribute their
  mappings. Unknown mappings fail at runtime without invalidating preserved data.
- Bounded scoped history retains initial entries, comments, inactive codes and
  nullable or agent actor identities with deterministic timestamp/id cursors.
- Coordination runs, work items, human actions and external dispatch are later
  slices. This status kernel does not claim to resume durable runs or deliver
  pending legacy outbox messages.
- The public API and contribution shape are documented in
  `apps/base/workflow/docs/README.md`; validation owns the executable contract.
