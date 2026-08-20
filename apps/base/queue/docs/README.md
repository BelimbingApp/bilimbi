# base/queue

Base Queue owns Bilimbi's durable background-work transport. It uses one named
Oban 2.23 instance on `Bilimbi.Base.Repo`, but Oban schemas and changesets are
private implementation details.

Capability modules own their worker logic, business idempotency records, and
durable business outcomes. They use `Bilimbi.Base.Queue.Worker` with a stable
lowercase worker ID on the supported `default` queue. Enqueue validates and
normalizes arguments through the worker before insertion, then rechecks the
bounded JSON shape. IDs and plain facts are appropriate arguments; credentials,
password hashes, schemas, PIDs, functions, unexpected fields, and other
process-local values are rejected or removed before persistence.

## Delivery semantics

Queue delivery is at least once. Oban uniqueness reduces duplicate insertion;
it does not serialize execution and is not business idempotency. A worker that
can cause a repeated business effect must enforce a durable invariant in the
module that owns that effect.

Use `Queue.enqueue/2` for ordinary durable work. Use the `Ecto.Multi` form when
a business write and its job must commit or roll back together. The Queue
facade never opens a separate transaction around that operation.

Retryable failures exhaust `max_attempts` and become discarded. Explicit
permanent failures become cancelled. Operators may cancel or retry a positive
job ID, but Queue exposes no broad mutation query and no manual discard action.
Worker failure codes are compile-time atoms with a bounded lowercase identifier
shape; caller-derived strings are replaced with a generic code before Oban can
persist or emit them.

## Operations and privacy

Operational pages and diagnostics expose only job IDs, stable worker IDs,
queue/state/attempt counts, timestamps, availability, and fixed aggregates.
They never return arguments, metadata beyond the stable ID, error text, stack
traces, database URLs, or legacy Laravel payloads.

Completed, cancelled, and discarded jobs are retained for seven days by the
Pruner plugin. The normal shutdown grace period is 15 seconds: fetching stops,
in-flight execution receives the grace window, and unfinished work remains
eligible for retry after restart.

## Migration, cutover, and rollback

The Oban v14 schema is a Bilimbi-only migration. Existing Laravel `jobs`,
`job_batches`, and `failed_jobs` relations remain inert and must never be read,
translated, renamed, or repurposed.

The configured PostgreSQL prefix is one Queue runtime fact shared by Oban and
the Queue facade's direct diagnostic reads. A non-public prefix must be supplied
to both migration and runtime configuration; splitting them is unsupported.

Cutover sequence:

1. Stop Laravel producers and drain or explicitly disposition its workers.
2. Deploy Bilimbi and run `mix bilimbi.migrate`.
3. Confirm Queue diagnostics are available and empty or expected.
4. Enable Bilimbi producers and workers.

Before removing or renaming a capability worker adapter, stop new insertion and
prove no available, scheduled, retryable, or executing jobs remain for its
stable ID. For rollback, stop Bilimbi producers/workers and restore the previous
release; Laravel continues to use only its own inert relations during the
agreed rollback window.
