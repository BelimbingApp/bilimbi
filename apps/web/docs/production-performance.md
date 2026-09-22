# Local production performance check

Measured on 2026-09-22 against baseline commit `246709cd` and the bounded
dashboard summaries. This is a local production-build comparison, not a deployed
service benchmark or a PHP-versus-Elixir benchmark.

## Method

- Detached temporary checkout, `MIX_ENV=prod mix compile` and
  `MIX_ENV=prod mix assets.deploy`; code reloading disabled, minified assets,
  logger explicitly configured at `:info` in the temporary launcher.
- Loopback-only HTTP endpoint on port 4010. Separate copy of the local development
  PostgreSQL database. No migrations or benchmark fixtures in the working database.
- Scheduler and job execution disabled, with mail routed to the test adapter.
  Request authentication, authorization, audit and performance recording retained.
- Initial smoke sample used the copied one-company/one-user dataset. Scaling
  sample added 1,000 companies and 10,000 synthetic users with disabled credentials;
  the final totals were 1,001 companies and 10,001 users in one tenant.
- Edge, authenticated WebSocket navigation, 25-row administration pages. A
  temporary browser probe measured `phx:page-loading-start` (redirect) to
  `phx:page-loading-stop`. This measures navigation completion, not guaranteed paint.
- Temporary server telemetry measured the complete LiveView mount (including
  authentication hooks), database query count and returned rows, without recording
  parameters or account identities. SQL plans were obtained from the actual public
  read APIs with `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.
- Repeated warm navigation samples are reported separately from cold startup and
  document reloads. This small single-user sample does not establish service p95,
  concurrency limits, WAN latency, or performance with different data distributions.

## Final comparison

These samples were collected after the test suite completed, with explicit
production logging. Ten warm Users → Dashboard transitions per version:

| Measurement | Before | After |
|---|---:|---:|
| Dashboard server mount, median | 64.5 ms | 32.4 ms |
| Dashboard server mount, maximum sampled | 81.1 ms | 40.4 ms |
| Browser navigation completion, median | 90 ms | 67.5 ms |
| Browser navigation completion, maximum sampled | 114 ms | 73 ms |
| Queries per authenticated dashboard mount | 38 | 38 |
| Database rows returned during that mount | 13,073 | 2,077 |

Browser navigation samples in milliseconds, before:
`84, 114, 76, 96, 96, 75, 83, 97, 97, 81`;
after: `70, 61, 73, 71, 68, 67, 61, 64, 65, 73`.
The server median roughly halved; the browser median improved by 25%.
The unchanged query count is intentional: less data is materialized per read,
without removing authentication, permission or audit work.

Three final warm document loads measured 61/86/66 ms to first byte and
126/163/125 ms to DOM content loaded. These include browser/network work and
are separate from LiveView navigation; no claim is made about cold deployment
startup. The temporary checkout, benchmark server, database copy and browser
instrumentation were removed after verification.

## What changed

The dashboard previously materialized every visible Company and User to compute
counts, then displayed one company and five users. The domain-owned
`Company.dashboard_summary/2` and `User.dashboard_summary/1` now compute counts
with window aggregates while returning only the displayed records. Each summary's
counts and records share one statement snapshot. User company membership still
comes through Company's public API, including archived companies; Company counts
still exclude archived companies. Neither permissions nor identity are cached.

On the scaling dataset, the dashboard's own Company/User record reads shrink from
1,001/10,001 records to 1/5. Across the whole authenticated mount, returned database
rows fall from 13,073 to 2,077. That includes company-ID lists, settings, count rows
and audit work; it is not a count of rendered records. Query count stays at 38.

## Query-plan findings and remaining work

The optimized user summary returned five rows in a sampled 7.5 ms SQL execution;
the company summary returned one in 1.9 ms. The Users index returned 25 rows in
8.6 ms; the Company index count/page statements took 0.3/1.3 ms. These isolated
plan timings include PostgreSQL instrumentation and should not be compared directly
with browser timings. No sampled plan spilled sorting to disk. Sequential scans
used for tenant-wide counts are expected; the observations do not justify an index
change by themselves.

The shell still resolves settings and company membership repeatedly. In the initial
profile, 17 settings queries accounted for about 4 ms of database time. Company-ID
lists remain proportional to tenant company count. If production traces show these
dominating under network latency or larger tenant populations, batch the owning
module APIs deliberately. Avoid cross-module private-table joins or stale
authorization caches to save those reads.

Load-test a deployed production-like environment before setting latency or capacity
targets. Include realistic role assignments, multi-tenant distributions, search,
sort, late pagination, concurrent users and database network latency.
