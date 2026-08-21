# Base Perf

Base Perf owns redacted, bounded operational performance history. Web attaches
Phoenix router, LiveView callback, and Ecto telemetry by starting this required
Base application; Queue's Oban telemetry is observed through the same reporter.
Observed business work never waits for or depends on history persistence.

History is stored in the Bilimbi-only `base_perf_samples` PostgreSQL ledger.
That makes one global history authoritative across nodes and durable across
restarts without inventing a Belimbing-compatible table. The ingress queue is
bounded per node, database failures drop observations, and a Schedule-owned
daily recurrence invokes the Perf-owned idempotent retention worker. Retention
enforces both age and row-count bounds. Each reporter also reconciles the cap
after every 100 accepted writes, bounding overshoot to at most 99 rows per live
node between reconciliations. Concurrent pruning is idempotent PostgreSQL work.

A separate sampler records coarse BEAM memory and run-queue pressure once per
minute. Telemetry-adapter restarts replace their handler generation; an
observation begun under an older generation is discarded at its terminal event
instead of being attributed across a restart. A new start always replaces stale
state in a reused request, LiveView, or Queue process.

Only stable route templates, bounded LiveView module identities, and Queue
worker IDs, coarse outcomes, durations, query timing/count, response-size
classes, and aggregate BEAM pressure are stored. Raw SQL, bind values, query
strings, event parameters, bodies, job arguments, exception payloads,
stacktraces, tenant/company/user identity, credentials, and arbitrary telemetry
metadata never enter the changeset.

The operator page exposes recorder backlog/drop degradation and SQL-bounded
recent regression candidates. System Info consumes the same redacted health
boundary. Each editable Perf definition requires `admin.system.perf.manage` in
addition to access to the generic settings screen; unauthorized fields are
excluded from both rendering and the server-side submission plan.

`BilimbiWeb.PerfTelemetry` is the Phoenix/Ecto adapter and attaches those host
events to the Base API. Base Perf itself attaches only Queue's Oban events and
has no dependency on Web; Web depends on the composed Base application in the
normal downward direction.
