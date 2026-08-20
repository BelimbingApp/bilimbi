# base/queue

Base Queue owns Bilimbi's durable background-work transport. It uses one named
Oban 2.23 instance on `Bilimbi.Base.Repo`, but Oban schemas and changesets are
private implementation details.

Capability modules own their worker logic, business idempotency records, and
durable business outcomes. They use `Bilimbi.Base.Queue.Worker` with a stable
lowercase worker ID and enqueue only bounded JSON data. IDs and plain facts are
appropriate arguments; credentials, password hashes, schemas, PIDs, functions,
and other process-local values are rejected.

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
