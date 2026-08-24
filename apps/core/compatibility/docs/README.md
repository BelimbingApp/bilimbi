# Core Compatibility

`apps/core/compatibility/` is the complete physical boundary for the required
`core/compatibility` module. Its public API is `Bilimbi.Core.Compatibility`.

The module coordinates fresh migration, structural verification, and explicit
adoption for the currently installed Base and Core modules. It owns no business
tables or migrations: each module ships its own migration path, while
Compatibility orders those paths through `Bilimbi.Base.Repo` and the shared
`bilimbi_schema_migrations` ledger.

This is a one-direction replacement boundary. Bilimbi verifies and adopts an
existing Belimbing database so Bilimbi can replace the Belimbing application.
After adoption, Bilimbi-only migrations and capabilities may evolve the
database without preserving the ability to run Belimbing again. Compatibility
protects durable incoming data and business meaning; it does not require
reverse migration, dual-running, or parity with Laravel source, routes, or UI.

Every owned migration version is explicitly classified by its descriptor.
Adoption records only verified compatible baselines and leaves Bilimbi-only
migrations pending. Recorded versions must be installed, and the recorded
versions in each class must be a prefix of that class's deterministic sequence.
The operational `mix bilimbi.migrate` command validates that state through this
module before choosing strict timestamp ordering. A class-valid gap may occur
when a later compatible baseline was adopted while an earlier Bilimbi-only
migration remains pending; arbitrary, foreign, or class-non-prefix ledgers fail
closed.

## Platform baseline failure evidence

The ExUnit console or GitHub Actions job log is the authoritative failure
record. Read it before rerunning. The repository currently retains Actions job
logs for 90 days. When `PlatformBaselineE2ETest` fails, its test-only
diagnostics also write a bounded, redacted JSON supplement below
`_build/test/e2e-diagnostics/` locally. In GitHub Actions, the failed Tests run
uploads the same JSON from runner temporary storage as a
`platform-baseline-failure-<run>-<attempt>` artifact for 14 days.

The supplement records the test and seed, original redacted exception and
stack, allowlisted nested Mix command status/output, runtime versions, three
pool-size integers, and fixed PostgreSQL connection/database aggregates. It
does not contain raw PostgreSQL logs, queries, business rows, Repo
configuration, process or environment dumps, credentials, tokens, hashes, or
payloads. The artifact is intentionally supplementary: the Actions log retains
the parent shell exit status, and diagnostic collection never retries or
changes that status.

For a focused local run, set `BILIMBI_E2E_PARENT_COMMAND` to `mix test`, run
`mix test test/platform_baseline_e2e_test.exs` directly from this package, and
inspect the console followed by `_build/test/e2e-diagnostics/` if it fails. To
retain the complete local console, redirect it to an ignored `_build/` file and
explicitly return the saved shell status. Treat that console file as sensitive;
it is never uploaded by the diagnostics workflow.
