# Base Perf

Base Perf owns redacted, bounded operational performance history. Web attaches
Phoenix and Ecto telemetry by starting this required Base application; Queue's
Oban telemetry is observed through the same reporter. Observed business work
never waits for or depends on history persistence.

History is stored in the Bilimbi-only `base_perf_samples` PostgreSQL ledger.
That makes one global history authoritative across nodes and durable across
restarts without inventing a Belimbing-compatible table. The ingress queue is
bounded per node, database failures drop observations, and a Schedule-owned
daily recurrence invokes the Perf-owned idempotent retention worker. Retention
enforces both age and row-count bounds.

Only stable route templates and Queue worker IDs, coarse outcomes, durations,
query timing/count, response-size classes, and aggregate BEAM pressure are
stored. Raw SQL, bind values, query strings, bodies, job arguments, exception
payloads, stacktraces, tenant/company/user identity, credentials, and arbitrary
telemetry metadata never enter the changeset.
