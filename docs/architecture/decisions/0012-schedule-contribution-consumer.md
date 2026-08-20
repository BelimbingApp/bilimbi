# ADR 0012: Schedule recurrence as a contribution consumer

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** codex/sol-hard-tasks
**Scope:** Deterministic installation-global recurrence registration
**Last Updated:** 2026-08-21

## Context

ADR 0004 established one descriptor-owned provider and an eager immutable
snapshot for installed-module contributions. ADR 0009 added Dashboard as a
peer consumer, and ADR 0011 added Principal Directory. Base Schedule needs the
same ownership and discovery guarantees for recurrence definitions: a module
must own its durable key, timezone, policy, worker, and bounded arguments
without a topology glob, mutable application-environment provider list, or a
second dependency graph.

A schedule definition contains executable identity, but the contribution
snapshot must remain plain data. The existing ADR 0004 rule already provides
the seam: a payload may name a module that implements an explicit behavior,
and its consumer validates that module eagerly.

## Decision

`:schedule` is a peer ModuleRegistry contribution consumer. Its payload is a
map containing `definitions`; Base Schedule's validator resolves each entry
with descriptor provenance and rejects malformed or duplicate durable keys,
non-five-field cron expressions, unknown IANA timezones, unsupported overlap
or misfire policies, non-plain arguments, and modules that do not implement
`Bilimbi.Base.Schedule.Worker`.

Definitions are installation-global immutable source facts. They are ordered
only through the validated dependency-first module graph and published in the
same one-time contribution snapshot as every other consumer. A provider may
name a worker module but may not return a closure or perform runtime I/O.

The current definition fingerprint is persisted only as explicit operator
review state. New or materially changed definitions fail closed until their
exact fingerprint is reviewed and enabled. A queued occurrence carries that
fingerprint and reauthorizes it immediately before business execution, so a
later suppression, disable, removal, or material definition change prevents
the stale job from running.

Base Queue remains the transport owner. Schedule may ask Queue for one bounded
job state to reconcile terminal cancellation, discard, completion, or pruning
with its own occurrence lease. Queue does not depend on Schedule and does not
learn recurrence semantics.

## Consequences

- `ContributionProvider.consumer()` and `ContributionRegistry` include
  `:schedule`, with validation owned by Base Schedule.
- Required consumers still receive their own validated empty shape when no
  installed module contributes entries.
- Capability modules own business idempotency and durable effects; Schedule's
  occurrence claim prevents duplicate enqueue but does not promise exactly-once
  business execution.
- Suppression and review uncertainty fail closed both at enqueue and execution.
- Queue terminal-state reconciliation releases Schedule overlap leases without
  creating a reverse Base Queue dependency.

## Alternatives considered

### Application-environment provider lists

Rejected. They are mutable deployment configuration, bypass installed-module
provenance, and create a second ordering and ownership mechanism.

### Filesystem or module reflection discovery

Rejected. It can find uninstalled code and recreates topology knowledge already
owned by ModuleRegistry.

### Queue-owned recurrence callbacks

Rejected. Queue owns transport, not capability-specific occurrence state. A
reverse Queue-to-Schedule dependency would invert the Base module boundary;
bounded state reconciliation preserves both ownership directions.
