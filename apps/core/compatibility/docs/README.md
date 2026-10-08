# Core Compatibility

The normative migration, verification, adoption, and ownership rules live in
[Bilimbi Database Architecture](../../../../docs/architecture/database.md).
This module document describes Core Compatibility's owned coordinator behavior;
it does not define a second database architecture.

`apps/core/compatibility/` is the complete physical boundary for the required
`core/compatibility` module. Its public API is `Bilimbi.Core.Compatibility` for
the schema lifecycle and `Bilimbi.Core.Compatibility.Cutover` for the one-shot
stored-value remediation described below.

The module coordinates fresh migration, structural verification, and explicit
adoption for every installed Platform, Domain, or Extension module. It owns no business
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
migrations pending. Recorded versions must be installed, and for each owner
the recorded versions in each class must be a prefix of that owner's class
sequence. Owners are independent: a Domain or Extension mounted after the
Platform migrated ships earlier-dated versions that are all pending, and an
absent owner (below) keeps its baseline pending behind recorded Platform
baselines; a later compatible baseline may likewise be adopted while an
earlier Bilimbi-only migration remains pending. `mix bilimbi.migrate`
validates the ledger through this module before running anything, and the
pending migrations then run after every recorded one, in version order among
themselves. `Ecto.Migrator.run/4` never refuses an older pending version
itself, so this validation is the ordering guard. A gap inside one owner's
sequence, and an arbitrary or foreign ledger, fail closed.

A recorded version that no installed migration ships belonged to a Domain or
Extension that has since been unmounted, or it is unexplained. The private
`Bilimbi.Core.Compatibility.MigrationProvenance` tells the two apart from
`bilimbi_migration_provenance`, which every migrate and adoption writes for
each applied version: owner ID, owner layer, disposition, and file checksum.
Only a retired Domain or Extension owner explains a missing version; a remount
must match the retained owner, disposition, and checksum. The contract is in
[Bilimbi Database Architecture](../../../../docs/architecture/database.md)
under "Ledger and execution".

## A mounted Domain or Extension the database never had

A Domain or Extension maps a Belimbing module an installation may never have
installed: Factory Inventory's compatible baseline is Belimbing's Commerce
item master, and a customer without Commerce has no such table. That owner
is absent, not drift, when none of the tables its schema contract names
exists, none of the objects it contributes to other tables exists, and none
of its versions is recorded (`Bilimbi.Core.Compatibility.absent_modules/2`).
Verification skips it, adoption records every other owner's baselines and
leaves its unrecorded, and `mix bilimbi.migrate` creates its baseline and
runs its Bilimbi-only migrations as on a fresh database. The verify and
adopt commands print one line per absent owner so the operator knows what
migrate will create.

A partly present owner is still drift: one table missing while another
exists, a present table that differs from the contract, or a contributed
object found while the tables are missing. The Platform is never absent;
Base and Core map Belimbing's own tables, so a Platform module with none is
a database behind the compatibility source. The decision and its reasoning
are [ADR 0020](../../../../docs/architecture/decisions/0020-per-owner-ledger-and-absent-optional-structure.md).

A Domain or Extension may therefore be mounted before the first adoption or
later, on an installation that has already taken newer Platform migrations;
the per-owner ledger rule above accepts its pending versions either way.

## Cutover value remediation

Adoption proves shape; it cannot prove meaning. Some adopted rows load cleanly
and then behave wrongly because Bilimbi reads the stored value differently:
`/admin/...` URLs in `user_pins` and notification payloads, `heroicon-` icon
names, and grants naming capabilities Bilimbi does not declare.
`Bilimbi.Core.Compatibility.Cutover`, driven by `mix bilimbi.cutover.remap`,
is the one grouped step that remediates those values, run once after adoption
and before traffic. Its place in the operational sequence belongs to
[Bilimbi Database Architecture](../../../../docs/architecture/database.md);
the exact cases, the counting rules, and the residue contract are documented
on the `Cutover` moduledoc.

Nothing is deleted. For the values the step must not decide on the operator's
behalf — an undeclared grant, a pin whose URL has no Bilimbi route — the
report naming each affected row is the entire remedy, so that report, not the
changed count, is what a cutover operator reads.

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
