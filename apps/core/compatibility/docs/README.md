# Core Compatibility

`apps/core/compatibility/` is the complete physical boundary for the required
`core/compatibility` module. Its public API is `Bilimbi.Core.Compatibility`.

The module coordinates fresh migration, structural verification, and explicit
adoption for the currently installed Base and Core modules. It owns no business
tables or migrations: each module ships its own migration path, while
Compatibility orders those paths through `Bilimbi.Base.Repo` and the shared
`bilimbi_schema_migrations` ledger.

Adoption may create an empty Bilimbi ledger or advance an exact earlier prefix
only after the complete installed schema verifies. It never replays DDL over an
existing Belimbing structure or accepts a foreign/non-prefix ledger.

## Platform baseline failure evidence

The ExUnit console or GitHub Actions job log is the authoritative failure
record. Read it before rerunning. When `PlatformBaselineE2ETest` fails, its
test-only diagnostics also write a bounded, redacted JSON supplement under
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
