# ADR 0020: Per-owner migration ledger and absent optional structure at adoption

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** claude/fable-5.1
**Scope:** The migration ledger rule `mix bilimbi.migrate` and `mix bilimbi.schema.adopt` enforce, and what verification and adoption do with a mounted Domain or Extension whose owned structure does not exist in the database
**Last Updated:** 2026-10-08

> This record amends two rules of [ADR 0002](./0002-compatible-schema-baselines.md):
> the ledger prefix is judged per owner, and a Domain or Extension whose
> owned structure is wholly absent is left for `migrate` instead of being
> refused as drift. The normative operating rules stay in
> [Bilimbi Database Architecture](../database.md).

## Context

ADR 0002 made the migration ledger safe with one rule: the recorded versions
of each disposition class must be a prefix of that class's installed
sequence, across every installed module. Verification was equally uniform:
every table a schema contract names must exist and match.

Both rules assumed the installed composition is fixed before the first
migration. A mounted Domain breaks that assumption twice. Rehearsing the
adoption of a Belimbing database shaped like a manufacturing customer's,
with the Factory Domain mounted, found:

- Factory Inventory declares Belimbing's Commerce item master,
  `commerce_inventory_items`, as its compatible baseline. The customer never
  installed Belimbing's Commerce module, so verification reported the table
  missing and adoption refused the whole database as drift. There was no
  supported way to adopt it with Factory mounted.
- Mounted instead after the Platform had been adopted and migrated, Factory's
  migrations, dated earlier than Platform migrations already recorded, made
  the recorded versions a non-prefix of the installed class sequence, and
  `mix bilimbi.migrate` refused the ledger. A Domain could not be added to an
  installation that had taken newer Platform migrations.

The second failure is not specific to Factory: any Domain or Extension is
developed on its own clock, so its versions interleave with the Platform's,
and an installation mounts it when the business needs it, not when the
database was created.

## Decision

### The ledger is a prefix per owner and class

For each installed module and each disposition class, the recorded versions
must be a prefix of that owner's class sequence. Owners are independent of
one another. Every recorded version must still be explained by an installed
migration or by retained provenance for a retired Domain or Extension, with
the owner, disposition, and checksum checks of
[ADR 0002](./0002-compatible-schema-baselines.md) and the provenance table
unchanged.

What the global rule caught that the per-owner rule accepts is a version
recorded while an earlier version of another owner is pending. That state is
now expected in two cases: a Domain or Extension mounted after the Platform
migrated, whose versions are all pending, and the absent owner below, whose
baseline stays pending behind recorded Platform baselines. In both the
pending migrations run after every recorded one, in version order among
themselves, so a later-mounted owner's migrations run against the dependency
structure that already exists. A migration that needs structure the Platform
has since changed fails at its own DDL, loudly, as it would on any upgrade.

What the per-owner rule keeps: a gap inside one owner's sequence, a version
nothing explains, and a remount under an applied version with a different
file or owner all fail closed. `Ecto.Migrator.run/4` never refused an
older pending version itself; the ledger validation in Core Compatibility is
the only guard, and it now says so.

### An absent Domain or Extension is created, not refused

A Domain or Extension maps a Belimbing module an installation may never have
had. When none of the tables its schema contract names exists, none of the
objects it contributes to other tables exists, and none of its versions is
recorded, the owner is absent:

- verification does not report its tables as missing and runs no invariant
  of its;
- adoption records every other owner's compatible baselines and leaves the
  absent owner's unrecorded; and
- `mix bilimbi.migrate` then creates the baseline and runs the owner's
  Bilimbi-only migrations, exactly as on a fresh database.

The verify and adopt commands name each absent owner, so the operator knows
which baselines the migrate step will create rather than adopt. An owner
with a recorded version is never absent: its structure was applied, and a
table missing afterwards is drift.

The rule is deliberately narrow. A partly present owner, one of its tables
missing or a present table differing from the contract, is drift as before.
The Platform cannot be absent: Base and Core map Belimbing's own tables,
pinned to the compatibility source, so a Platform module with no tables is a
database behind that source, which Belimbing must upgrade first because its
upgrade steps may carry data backfills Bilimbi does not replay.

The rule relies on a contract listing exactly the tables the owner's
compatible baselines create. A Domain that put a Bilimbi-only table in
`tables/0` would be partly present on every Belimbing database that has its
Belimbing module, and absent on none.

## Consequences

- A manufacturing customer's Belimbing database adopts with Factory mounted,
  and the migrate step creates the Commerce item master the customer never
  had.
- A Domain or Extension can be mounted before the first adoption or at any
  later time; the ledger needs no renumbering and no manual rows.
- The compatibility README owns the operating description of both rules, and
  Core Compatibility's `absent_modules/2` is the one source for which owners
  are absent.
- Core Compatibility no longer computes a strict-order flag for Ecto; its
  own validation is the ordering guard.
