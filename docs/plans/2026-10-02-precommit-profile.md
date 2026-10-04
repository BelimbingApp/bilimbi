# docs/plans/2026-10-02-precommit-profile.md

**Status:** Measurement record — one matched run on a shared machine; the numbers are not kept current
**Last Updated:** 2026-10-02

# CI performance measurements

## Method

The baseline is Platform commit `e33f28b0838aa2eb266a48c5094ad66287490abb`.
Measurements use the same worktree, installed optional Domain composition,
Elixir 1.20.3 / OTP 28.5, PostgreSQL 18, existing dependency and build caches,
and a fixed BEAM scheduler limit on each comparison. The machine and PostgreSQL
server are shared with other work, so individual timings vary with load and
randomized test order.
Logs stay outside the tracked tree.

```sh
/usr/bin/time -p env MIX_ENV=test ERL_FLAGS='+S 2:2' mix precommit
```

The full command includes compilation, formatting, asset hook tests, all
installed package suites, real-host integration tests, and contribution
verification. No suite was omitted. The baseline already has one excluded
optional-module test; that exclusion is unchanged.

For detailed profiling, use `mix precommit.test --slowest 10 --slowest-modules 5`,
or run those flags in a particular package. Elixir makes `--slowest` enable trace
and serial test execution, so those runs are diagnostic rather than comparable
full-run benchmarks. Package wall times printed by `precommit.test` include
VM startup, compilation, helper loading, and database setup, unlike ExUnit's
reported test duration.

The matched comparison uses two schedulers and runs baseline and implementation
back to back. Both sides retain the same collision-safe concurrency-database
names, so a preexisting VM-counter collision cannot abort the baseline. All
performance changes and added regression tests are absent on the baseline side.

An earlier comparison with twelve schedulers completed in 855.13 seconds before
and 1,155.61 seconds after. Machine load rose above 30 during the latter run;
unchanged Web tests doubled from 118.6 to 240.9 seconds. That unmatched sample
does not demonstrate an elapsed-time improvement. It did show 96 visible source
compilation batches (1,038 Elixir files) before and zero after. The matched
comparison below includes initial rebuilding when returning from baseline code.

## Full-run result

The matched full precommit improved from **26m06s to 23m53s**, saving **2m13s
(8.5%)**. Both commands exited successfully and verified eight installed
contribution snapshots.

| Measurement | Before | After |
| --- | ---: | ---: |
| Full precommit wall time | 1,565.98 s | 1,432.67 s |
| ExUnit tests passed | 2,458 | 2,462 |
| JavaScript tests passed | 134 | 134 |
| Existing excluded optional test | 1 | 1 |
| Visible Elixir compilation batches | 101 | 34 |
| Elixir files in those batches | 1,307 | 449 |
| Asset hook test duration | 2.553 s | 1.383 s |

Compilation counts cover the visible top-level logs; successful nested CLI
commands capture their own output. The after run includes rebuilding the test
closure following the baseline's production dependency builds. No test timeout,
assertion, password-hash setting, or database lifecycle check was relaxed.

ExUnit-reported durations by layer, separate from process/setup wall time:

| Suite | Before | After | After package wall time |
| --- | ---: | ---: | ---: |
| Core | 895.00 s | 894.00 s | 930.76 s |
| Base | 40.53 s | 55.28 s | 131.86 s |
| Web integrations | 186.00 s | 206.60 s | 225.00 s |
| Mounted Domains | 25.30 s | 30.10 s | 90.82 s |

Compatibility alone reported 861.4 seconds before and 866.2 seconds after;
it remains the largest cost. Summed ExUnit time increased from 1,146.83 to
1,185.98 seconds, including the added regressions. The remainder of the full
command fell from about 419.15 to 246.69 seconds, consistent with reduced build
and setup work rather than less test execution.

The baseline ran from 21:44:31 to 22:10:37 UTC on 2026-10-02; the implementation
ran immediately afterward until 22:34:30 UTC. One-minute machine load was 28.63
at baseline start, 11.38 at the transition, and 17.21 at implementation finish.
These are single samples on a shared machine, not a guarantee for a particular
CI runner. The deterministic build-retention regressions support the mechanism;
remote CI timing should be compared after publication.

## Lane G build-loop follow-up

The performance audit's hook collector baseline loaded 428 compiled modules in
a fresh Mix VM and spent **2,756 ms** doing so, despite finding no colocated
hooks. The collector now intersects the compiled application's module list with
the extracted `phoenix-colocated/<otp_app>/` directories and loads only those
owners. A fresh-VM direct collector call in the isolated implementation
worktree took **224 ms** and returned `{:noop, []}`. The existing unmount test
still retains extracted files and proves they do not re-enter the bundle.

The webhook registry lookup's empty-registry constraint is documented beside
`BilimbiWeb.Webhooks.deliver/2`. For the separate `compile.strict` requirement,
see [mounted-code traversal](../architecture/0010_composition-model.md#realization-outcome).

| Measurement | Audit baseline | Implementation worktree |
| --- | ---: | ---: |
| Hook collector, fresh VM | 2,756 ms | 224 ms |
| Root no-op `mix compile` | 11.0 s | 25.84 s |
| Focused colocated-hook tests | existing behavior | 4 passed |

The root compile samples are not a matched timing comparison: the audit had a
warm, mounted composition and its own shared build cache, while this disposable
worktree began without dependencies or compiled applications and does not have
the optional mounted repositories. The 25.84 s figure is reported as observed,
not as an improvement. The audit's mtime-keyed graph cache proposal was not
adopted: module discovery must keep reading changed file contents and
revalidating directories and migrations on every call, as specified in the
Module Registry guide. The existing full-content literal-data cache remains in
place.

## Changes

Local path dependencies now consistently use `:test` during test builds.
Previously their default `:prod` environment dropped compiled test support
from the shared `_build/test` tree, causing repeated compilation as a package
alternated between host dependency and test owner. Platform helpers now load
that support with `Code.ensure_loaded!/1` instead of compiling its source again.
Production dependency environments retain their existing behavior.

The full runner preserves separate package VMs and sequential execution.
Compatibility tests temporarily mount source and regenerate graph metadata;
parallelizing those suites against the same workspace would race. Profiling
arguments now reach every package, and the runner prints each package's wall time.

The transitive-version fixture now fetches and validates dependencies in one
fresh Mix VM per resolution, proving fetch success explicitly before checking
the validation result and locked revision. Both individually valid repositories
and both conflicting revisions are still exercised. The host-start regression
also runs strict compilation and startup together in its final fresh VM.

Fingerprinting reuses validated module and declared route paths instead of
walking the module tree again. Literal route data uses the existing full-content
parse-cache approach. Every call still reads file bytes and validates the graph;
executable route data is reevaluated. Regression tests cover same-size edits with
restored timestamps, deleted routes, and nonstandard route filenames.

Consistent builds exposed two previously masked integration problems. The host
graph compiler now refreshes its OTP application list when a container without
routes is unmounted. A real host-start regression covers test and production
builds. The Web test bootstrap loads every discovered helper before compiling
tests, working around Elixir 1.20.3's short-circuiting helper loader while keeping
warning diagnostics. All 39 integration tests affected by missing mounted
fixtures passed after this correction.

Isolated concurrency-test databases now use random identifiers rather than a
VM-local counter, avoiding collisions with other lanes or interrupted runs.
The tests still create and migrate their own databases and retain their existing
assertions and cleanup. No existing foreign database was removed.

CI separately caches Tailwind/esbuild binaries and npm downloads, keyed by
runner platform, configured versions, and the asset lockfile. Installation and
verification steps remain in place. This cache's remote benefit is not included
in the local elapsed-time measurement.

## Smaller measurements

Thirty calls in a single Mix process, using the same installed graph:

| Operation | Before | After |
| --- | ---: | ---: |
| Workspace discovery | 0.261 s | 0.213 s |
| Route manifest generation | 0.473 s | 0.303 s |
| Workspace fingerprinting | 0.564 s | 0.386 s |

The asset hook runner reported 1.072 seconds before the change. A separate
Audit fixture probe took 1.655 seconds for 100 table setups in fresh sandbox
tasks. Neither measurement justified changing fixture isolation or batching
database setup. Database rebuilds that exercise migration/adoption behavior,
password hashing, test timeouts, and test assertions remain intact.

The registry profile used `mix test --slowest 10 --slowest-modules 5` with two
schedulers. It passed all 89 tests. The transitive-version conflict case was
slowest at 14.498 seconds, and the two new build cases took 18.807 seconds
combined. After batching their final tasks, the focused ten-test profile passed;
those durations were 4.762 and 16.151 seconds respectively. Each resolution still
checks fetch success, the locked revision, and the real Mix validation result.
