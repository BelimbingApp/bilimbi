# base/queue

Base Queue owns Bilimbi's durable background-work transport. It uses one named
Oban 2.23 instance on `Bilimbi.Base.Repo`, but Oban schemas and changesets are
private implementation details.

Capability modules own their worker logic, business idempotency records, and
durable business outcomes. They use `Bilimbi.Base.Queue.Worker` with a stable
lowercase worker ID on the supported `default` queue. Enqueue validates and
normalizes arguments through the worker before insertion, then rechecks the
bounded JSON shape.

The framework's argument validation limits JSON shape, depth, member count, and
encoded size; it does not know which worker fields are expected or sensitive.
Every worker's `validate_args/1` is therefore its persistence allowlist. Match
the accepted input and return a newly narrowed map:

```elixir
def validate_args(%{"value" => value}) when is_integer(value),
  do: {:ok, %{"value" => value}}

def validate_args(_args), do: {:error, :invalid_value}
```

Returning the input map unchanged persists every structurally valid field in
`oban_jobs.args`. IDs and plain facts are appropriate arguments; credentials,
password hashes, schemas, PIDs, functions, unexpected fields, and other
process-local values must be rejected or removed before persistence.

## Work that acts for a user

`Queue.enqueue_for(scope, worker, args)` enqueues work on behalf of the scope's
signed-in user. The actor travels as a token Base Tenancy signs, stored in job
metadata that callers cannot write; it is never an argument. When the job runs,
`execution.scope` is that user's scope with the tenant re-proven live, and the
worker passes it to module APIs as a request would. A tampered or expired
token (one week), or a tenant gone since enqueue, cancels the job with
`:delegated_actor_unavailable` before the worker runs. The installed actor
verifier (Core User) then re-proves the user; a user who is gone, has left the
company, or whose impersonation has ended cancels the job with
`:delegated_actor_refused`, and a deployment with no verifier cancels it with
`:no_actor_verifier`. Whether the user may still perform the operation is
decided when it runs, by Base Authz against live grants. A system scope has no
one to act for; `enqueue_for/3` refuses it and ordinary work uses `enqueue/2`,
whose `execution.scope` is `nil`.

`enqueue_for/3` refuses a worker that declares `unique_period` with
`:unique_worker`. Oban's uniqueness compares arguments, not job metadata, so a
duplicate would be absorbed by a job carrying another user, or no user, and
the caller's request would run as them.

## Work that runs as a system principal

Routine work nobody signed in for, such as a scheduled import, runs as a
named system principal instead of borrowing a person's account (ADR 0017).
The worker declares the principal, and the module that owns the worker
declares the same name under its `:system_principals` contribution:

```elixir
use Bilimbi.Base.Queue.Worker,
  id: "coating/line-import",
  system_principal: "coating.line_import"
```

`Queue.enqueue_as_system(scope, company_id, worker, args)` is the only way to
enqueue such a worker; `enqueue/2` and `enqueue_for/3` refuse it with
`:system_principal_worker`. It refuses a worker that declares no principal
(`:not_system_principal_worker`), a name no installed module declares or a
worker that is not the declaring module's code
(`:undeclared_system_principal`), a company ID that is not positive
(`:invalid_company`), and a unique worker (`:unique_worker`). Only the
scope's tenant is used; whoever enqueued the job is not carried into it.

When the job runs, `execution.scope` names the principal in that tenant and
company, and captured writes record `actor_type` `"system"` with the
principal's name. A principal nobody declares any more cancels the job with
`:system_principal_refused`; a tampered, expired, or missing token, or a tenant
gone since enqueue, cancels it with `:system_principal_unavailable`. The
principal holds only what an administrator granted it in that company, decided
by Base Authz when the job asks.

A Schedule worker cannot declare a principal; Base Schedule refuses one at
boot, because a schedule definition names no tenant or company. To run
scheduled work as a principal, schedule a plain worker whose job builds the
tenant scope with `Bilimbi.Base.Tenancy.scope/1` and calls
`Queue.enqueue_as_system/4` with that scope, the company, and the principal
worker.

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
Pruner plugin. This is deliberately fixed transport retention, not an operator
setting: it keeps the Queue diagnostic and recovery window bounded and
consistent across installations. Capability modules that need longer,
auditable, or operator-configurable history own durable business records and
their retention policy; Oban job rows are not that ledger. The normal shutdown
grace period is 15 seconds: fetching stops, in-flight execution receives the
grace window, and unfinished work remains eligible for retry after restart.

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
