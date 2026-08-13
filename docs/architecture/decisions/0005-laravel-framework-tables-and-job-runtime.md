# ADR 0005: Laravel framework residue and the Bilimbi job runtime

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** codex/sol-high
**Scope:** Laravel framework tables, schema adoption, caching, and durable
background jobs
**Last Updated:** 2026-08-13

## Context

The pinned Belimbing source
`e70b4d33c0b10790e681f4c2b5095d85a53bc918` creates six Laravel framework
tables outside a deep module:

| Migration | Tables | Configured use |
|---|---|---|
| `database/migrations/0001_01_01_000001_create_cache_table.php` | `cache`, `cache_locks` | `config/cache.php` defaults `CACHE_STORE` to `database` |
| `database/migrations/0001_01_01_000002_create_jobs_table.php` | `jobs`, `job_batches`, `failed_jobs` | `config/queue.php` defaults `QUEUE_CONNECTION` to `database` |
| `database/migrations/0001_01_01_000003_create_sessions_table.php` | `sessions` | `config/session.php` defaults `SESSION_DRIVER` to `database` |

They do not have one shared business meaning. `sessions` is now an active
Bilimbi contract owned by Base Session. The cache rows are disposable Laravel
runtime state. The queue rows contain serialized Laravel job envelopes and
failure records that an Elixir worker cannot execute safely.

The queue is not hypothetical. Belimbing has queued work in Base PDF, Base
Schedule, Core Geonames, and Core AI. At the pinned source, thirteen classes
implement `ShouldQueue`; several select named queues and Core Geonames even
provides an explicit one-job worker fallback. Bilimbi currently has no queue
dependency or supervised durable worker runtime.

Adoption needs an explicit boundary. `SchemaVerifier` is strict inside each
installed module's table contract, while deliberately ignoring tables owned by
other modules. `Compatibility.adopt/2`, however, records every discovered
migration version after verification. That blanket rule works for current
Belimbing-compatible baselines, but it cannot safely adopt a future
Bilimbi-only Oban migration: an untouched Belimbing database does not contain
`oban_jobs`.

## Decision

### Classify the six framework tables by ownership

`sessions` is ported, not residue. Base Session owns its migration, exact
schema contract, runtime API, and current-scope integration. Verification and
adoption remain strict for the canonical table.

`cache` and `cache_locks` are intentionally not ported. Bilimbi code must not
read, write, refresh, or depend on Laravel's serialized cache values or locks.
An adopted database may retain those tables as inert Laravel-owned operational
residue. A fresh Bilimbi database does not create them. If a later capability
proves that shared durable caching is required, it receives a separate
inventory and contract; the existence of these tables is not evidence for
reusing their format.

`jobs`, `job_batches`, and `failed_jobs` are also not ported. They remain inert
Laravel-owned operational residue during adoption and are not Bilimbi's retry,
audit, or scheduling source of truth. A fresh Bilimbi database does not create
them, and Bilimbi never attempts to deserialize or execute their payloads.

This preserves the verifier's current allowlist boundary: installed contracts
define the structures Bilimbi owns and verifies exactly; unrelated tables do
not become drift merely because they share the PostgreSQL schema. That rule
also covers Laravel's `migrations` ledger. Ignoring an unowned table never
relaxes column, index, foreign-key, check, contribution, or live-data
verification for a table Bilimbi does own.

### Select Oban for durable background execution

Bilimbi will use Oban with the shared PostgreSQL Repo for admitted durable
background work. Oban is a better semantic match than Laravel's queue tables:
it provides an Elixir worker contract, persisted job state, bounded queues,
retries, scheduling, and test modes while using the database Bilimbi already
operates. Its official installation contract creates and evolves
`oban_jobs` through `Oban.Migration` and runs Oban under supervision.

The dependency is not added by this ADR. The first accepted S3 capability that
requires durable asynchronous execution must open a dedicated Base Queue task
which owns:

- the `apps/base/queue/**` module boundary and public enqueue contract;
- the serialized `mix.lock` claim and a deliberately pinned Oban version;
- Oban configuration, supervision, queue names, migration, compatibility
  contract, and operator diagnostics;
- manual test mode and focused retry, idempotency, cancellation, and shutdown
  tests; and
- operational documentation for worker availability, backlog, failure, and
  recovery.

Capability modules own their workers and business idempotency. Base Queue owns
transport and execution policy, not every capability's job names. Job
arguments must be stable data rather than Ecto structs or process-local state.
Enqueueing must occur transactionally with the business change when loss or a
phantom job would violate the capability contract. Oban uniqueness is an
insertion-time aid, not a substitute for idempotent business behavior.

### Extend adoption before adding a Bilimbi-only migration

The Base Queue implementation is blocked on an explicit migration-disposition
contract. Compatibility must distinguish at least:

1. **compatible baselines**, whose current structure already exists in a
   pinned Belimbing database and may be ledger-adopted after strict
   verification; and
2. **Bilimbi-only migrations**, which must execute normally and must never be
   marked complete merely because the Belimbing-compatible slice verified.

That distinction must remain deterministic, inspectable through the installed
module graph, and covered by fresh-database, untouched-Belimbing adoption, and
already-adopted-prefix tests. Until it exists, no Oban migration or dependency
may land. This prevents `bilimbi.schema.adopt` from recording an absent
`oban_jobs` table as migrated.

### Cut over without translating queued payloads

Deployment must stop Laravel producers, drain or explicitly abandon the
Laravel queue under an operator-approved cutoff, and only then enable Bilimbi
producers and Oban workers. The systems do not dual-consume one queue and no
automated payload translator is provided. Laravel framework tables remain
untouched through the rollback window; removing them is a later explicit
operator action, never an adoption side effect.

Capabilities with durable business records around a job—such as PDF artifacts
or AI run/event state—port those records under their owning contracts. Queue
rows themselves are execution machinery, not the durable business ledger.

## Consequences

- Existing Belimbing databases may keep all five unported cache/queue tables
  without failing schema adoption; owned Bilimbi tables remain drift-strict.
- Fresh Bilimbi databases create `sessions` but not Laravel cache or queue
  tables.
- Later asynchronous capabilities share one supervised PostgreSQL-backed
  execution substrate instead of inventing per-module processes or copying
  Laravel payload formats.
- Oban is selected, but dependency and runtime changes wait for an admitted S3
  implementation task and an independently reviewed adoption-disposition
  extension.
- Cutover requires an explicit queue drain/abandon decision; old failures and
  pending Laravel payloads are never silently treated as completed Bilimbi
  work.

## Rejected alternatives

**Treat every extra table as drift.** This would reject real Belimbing
databases for retaining framework and module tables outside the installed
Bilimbi slice, contradicting the verifier's ownership boundary.

**Reuse Laravel's `jobs` tables.** Their payload and lifecycle are framework
specific. Sharing storage would imply interoperability that does not exist and
would make rollback and ownership ambiguous.

**Use unsupervised `Task` processes as the platform queue.** They do not
provide durable backlog, retry, scheduling, or restart semantics required by
PDF, schedule, integration, workflow, and AI work.

**Add Oban immediately.** Under the current blanket adoption ledger, a
Bilimbi-only migration could be recorded without executing on an existing
Belimbing database. Selecting the runtime now while gating installation on the
migration-disposition contract keeps the decision useful without shipping an
unsafe adoption path.

## References

- [Oban installation](https://oban.hexdocs.pm/installation.html)
- [Oban unique jobs](https://oban.hexdocs.pm/unique_jobs.html)
- ADR 0002, “Compatible schema baselines and adoption”
- `apps/base/database/lib/database/schema_verifier.ex`
- `apps/core/compatibility/lib/compatibility.ex`
