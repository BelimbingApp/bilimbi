# Bilimbi Database Architecture

**Document Type:** Normative architecture specification

**Status:** Current

**Purpose:** Define Bilimbi's database ownership, dependency, migration,
compatibility, verification, adoption, and seeding rules.

**Last Updated:** 2026-09-23

## Purpose and authority

This document is the human-facing single source of truth for Bilimbi database
architecture. Read it before changing a persistent relation, migration, schema
contract, cross-module database dependency, production seed, or compatibility
workflow.

The specification does not duplicate the installed module graph or the live
database ledger. Those facts have machine-readable owners:

| Fact | Authoritative artifact |
| --- | --- |
| Database architecture and ownership rules | This document |
| Installed module identity, dependencies, migration path, migration dispositions, and schema-contract provider | The module's `bilimbi.module.exs` |
| Executable schema evolution | The owning Ecto migration source |
| Expected owned structure and live-data invariants | The owning module's `SchemaContract` |
| Applied Bilimbi migration state | `bilimbi_schema_migrations` in the target database |
| Production seed completion state | `bilimbi_production_seeds` in the target database |
| Historical design rationale | Accepted architecture decision records |

These artifacts must agree. Do not resolve disagreement by creating a second
hand-maintained module, table, migration, or dependency registry in Markdown.
Fix the authoritative artifact and update this specification when the
architecture itself changes.

## Database boundary

Bilimbi has one shared PostgreSQL database boundary and one Ecto Repo:
`Bilimbi.Base.Repo`, physically owned by `base/database`. The public Repo name
is a deliberate platform convention; it does not give Base Database ownership
of business tables or permission to bypass another module's API.

Each deep module owns its database assets inside its package:

```text
apps/<layer>/<module>/
├── bilimbi.module.exs
├── lib/
│   └── ... schema contract and private persistence implementation
└── priv/repo/migrations/
```

The owner publishes its migration path and schema-contract provider through
its descriptor. `core/compatibility` discovers installed contributions and
coordinates them generically through the shared Repo. It owns no business
table and must not contain a hard-coded list of module paths, relations, or
module-specific verification SQL.

## Ownership

A module owns a persistent relation when its business capability owns that
relation's durable meaning. Physical table naming, framework conventions, or
which screen first needs the data do not transfer ownership.

The relation owner owns:

- the canonical table, view, or function definition;
- columns whose meaning belongs to that relation;
- its primary key, sequences, indexes, checks, triggers, and local foreign
  keys;
- Ecto schemas, queries, changesets, and persistence policy;
- its compatible baseline or Bilimbi-only migrations;
- its schema contract and live-data invariants; and
- production/reference seed callbacks for its data.

Schemas and queryables are private implementation unless the owning module
explicitly defines a different public contract. Callers consume small public
APIs and schema-free values, not another module's Ecto schema or table helper.

### Cross-module foreign keys

A cross-module foreign key belongs to the depending module whose capability
introduces the reference. Its migration runs after the referenced relation
exists and adds the complete contribution atomically. The referenced relation
owner describes the contribution as an optional or required schema-contract
group so verification can distinguish an absent capability from a partly
applied constraint set.

For example, Core Employee creates the Company department-head foreign key
after `employees` exists, and Core User completes Company's external-access
User reference. A module must not add an index to a sibling-owned relation for
its own query without an explicit owner-reviewed migration decision; measured
need is implemented by the relation owner.

## Four dependency categories

"Depends on" is ambiguous unless the dependency category is named. Bilimbi
uses four distinct categories.

### 1. Module and API dependency

A descriptor edge authorizes compilation and calls to the dependency's public
contracts. Dependencies follow the composition rules in
[`0010_composition-model.md`](./0010_composition-model.md): they are explicit,
downward or permitted same-layer edges, and acyclic.

An API dependency does not authorize importing a private Ecto schema, querying
the dependency's tables, or writing its data. For example, `core/user` may
depend on `core/company` and call `Company.get_company/2`; the edge alone does
not grant access to the private Company schema.

### 2. Schema and foreign-key dependency

A schema dependency exists when one module's owned structure refers to another
module's relation or durable identifier. It must be represented by a declared
module dependency, an owner-placed migration contribution, and both owners'
schema-contract expectations where applicable.

### 3. Migration-order dependency

The referenced structure must exist before the depending migration runs.
Installed contributors are discovered in the validated descriptor graph;
dependencies precede dependants and the layer order is Base, Core, Domain,
then Extension. Globally unique Ecto versions provide the executable ordering
across the discovered paths and must preserve those dependencies.

Repository proximity, filename discovery order, and a table already existing
in one developer database are not ordering contracts.

### 4. Exceptional private-relation read

Some bounded relational workflows cannot preserve filtering, ordering,
pagination, aggregation, and one-snapshot semantics by composing public APIs.
Reading another module's private relation is still forbidden by default, even
when the descriptor dependency is legal.

An exception requires an explicit architecture decision that defines:

- one coherent business purpose and owner;
- exact relation, column, type, and nullability allowlists;
- one private source site;
- read-only, parameterized behavior with no schema or queryable exposure;
- a versioned consumed-relation manifest checked against owner contracts;
- source/AST guards that prevent copies, expansion, writes, dynamic
  identifiers, or raw-SQL escapes; and
- independent architecture, security, and database review proportional to
  the query.

The exception grants no general sibling persistence access and creates no
precedent for another query.

## Migration contract

Every module with migrations declares a relative `migrations` path in
`bilimbi.module.exs`. A descriptor with `migrations: nil` owns no migration
path and omits `migration_dispositions`.

A migration-owning descriptor maps every migration filename version exactly
once to one of:

- `:compatible_baseline` — creates structure Bilimbi can first verify and
  ledger-adopt from the pinned Belimbing schema; or
- `:bilimbi_only` — evolves an adopted or fresh database beyond the incoming
  Belimbing boundary and always executes when pending.

There is no default disposition. Missing, extra, invalid, or duplicate
versions fail discovery. Versions are globally unique across the installed
composition. Migration modules use the owning descriptor namespace.

Migrations express a real state transition. Do not use broad
`create_if_not_exists` or conditional DDL to conceal whether a database is
fresh, adopted, partly migrated, or drifting. A compatible baseline creates
the reviewed current state directly; it does not replay Laravel's historical
upgrade sequence.

## Ledger and execution

Bilimbi records applied versions only in `bilimbi_schema_migrations`. It never
reads, writes, renames, drops, adopts, or repurposes Laravel's `migrations`
table.

The normal operational commands are:

| Command | Purpose |
| --- | --- |
| `mix bilimbi.migrate` | Run every pending installed migration through the shared Repo after disposition and ledger validation, then grant the SQL console role its reads. |
| `mix bilimbi.migrations` | Display installed Bilimbi migration status. |
| `mix bilimbi.rollback` | Roll back installed migrations using all discovered migration paths and the shared ledger. |
| `mix bilimbi.schema.verify` | Read-only verification of owned structure, contributions, and live-data invariants. |
| `mix bilimbi.schema.adopt` | Re-verify an existing Belimbing schema and record only compatible-baseline versions without executing their DDL. |
| `mix bilimbi.cutover.remap` | Remap adopted Belimbing stored values Bilimbi reads differently, and report the residue. Run once at cutover, after adoption. |
| `mix bilimbi.seeds.run` | Run installed production seed providers through the separate production-seed ledger. |

Run migrations through these Bilimbi tasks rather than a single module path.
The installed graph is validated before migration paths are exposed;
`mix bilimbi.migrate` additionally validates dispositions and the ledger before
execution.

## Compatibility lifecycle

Compatibility is a one-direction replacement contract. Bilimbi must be able
to adopt the pinned Belimbing PostgreSQL schema, preserve its durable business
meaning and identifiers, and replace the Belimbing application. Belimbing is
not required to consume Bilimbi migrations or run after Bilimbi-only
evolution.

### Fresh database

A fresh database runs `mix bilimbi.migrate`. Compatible baselines and
Bilimbi-only migrations execute normally in global version order. Baselines
create the current compatible end state and do not create tenant, company,
User, or other identity-bearing business rows unless the owning migration's
durable contract explicitly requires data.

### Existing Belimbing database

An existing database follows three explicit steps:

1. `mix bilimbi.schema.verify` compares the live database with every installed
   schema contract and invariant.
2. `mix bilimbi.schema.adopt` repeats verification under the adoption lock and
   records only compatible-baseline versions without executing their DDL.
3. `mix bilimbi.cutover.remap` remaps stored values Bilimbi interprets
   differently (pin and notification URLs with recomputed hashes, icon names)
   and reports the residue it must not fix: grants naming capabilities
   Bilimbi does not declare, and pins with no Bilimbi equivalent, which stay
   in place by captain's decision. Nothing is ever deleted.

Adoption refuses structural drift, invariant failures, unknown ledger
versions, and invalid class ordering. It never modifies business data or
Laravel's ledger. Pending Bilimbi-only migrations remain pending and run later
through `mix bilimbi.migrate`.

Run the remap's `--dry-run` first on cutover day (it is the read-only
value verifier: shape verification stays `bilimbi.schema.verify`), read the
residue it names, then run the real remap before opening traffic. Pass the
same `--prefix` the two schema steps used. The run is idempotent; reruns
report `changed: 0`.

The detailed historical decision and pinned compatibility source remain in
[ADR 0002](./decisions/0002-compatible-schema-baselines.md).

## Schema contracts and verification

Each persistence owner exposes its structural contract through the
`schema_contract` named in its descriptor. Contracts describe the exact owned
tables and contributions that Compatibility can verify generically, including
columns, PostgreSQL types, nullability, defaults, named indexes, predicates,
foreign keys, and checks supported by the verifier.

The same contract owns any live-data invariant understood by the module.
Compatibility discovers contracts and aggregates their results; it must not
learn tenant-, company-, address-, or future module-specific SQL.

A structural contract records expected durable structure. It does not grant
runtime query authority. An exceptional reader's consumed-relation manifest
may compare its expectations with an owner contract, but that comparison is a
compatibility check, not access permission.

## Production and development data

Schema migrations create structure and only the durable data required by that
state transition. Reference data and operational seed workflows remain
separate and module-owned.

Production seed providers use stable logical IDs, declare dependencies, and
run through `mix bilimbi.seeds.run`. Their completion state belongs to
`bilimbi_production_seeds`, not the migration ledger or Laravel's
`base_database_seeders`. Providers must be idempotent or safely resumable
because adopted databases do not import Laravel seeder completion identities.

Development, demonstration, and test fixtures are not production seeds. Test
DDL and fixtures remain defined once by their owning module; cross-module
tests use public APIs or declared test support from dependencies.

## Operator SQL console

The operator SQL console (`Bilimbi.Base.Database.execute_readonly/3`, the
`/admin/system/database-queries` pages) is the one product surface that runs
caller-authored SQL. It does not run through `Bilimbi.Base.Repo`. It runs
through `Bilimbi.Base.Database.ConsoleRepo`, a second connection whose
PostgreSQL role holds `SELECT` and nothing else, so a write is refused by the
database on privileges whatever the query says and whatever the application
checks. The executor's `SELECT`/`WITH` and forbidden-keyword text checks give
early, readable refusals; they are not the boundary. Its `READ ONLY`
transaction backs the role up for what privileges do not cover, such as
temporary objects. ADR 0016 records the decision.

**Where the role lives.** A PostgreSQL role is cluster state, not database
state, and needs a credential, so it is provisioned outside the application
the same way the application's own login is: by whoever operates the
cluster, once, as a superuser. Migrations, seeds, and the running application
never create it.

```sql
CREATE ROLE bilimbi_console LOGIN PASSWORD '<password>';
```

Development and CI use the name and password in `config/dev.exs`; production
names the role's own connection string in `CONSOLE_DATABASE_URL`, and boot
refuses without it rather than letting the console reach the read-write
login. The role name is whatever that connection uses.

**What it reads.** `mix bilimbi.migrate` ends by granting the role exactly
its reads in the migrated prefix, through the application's own Repo, which
owns the tables:

- `SELECT` on every table and view in the prefix. Schema contracts pin only
  the compatible baseline, and the tables Bilimbi has added since (schedule
  occurrences, postcode overrides, perf samples, Oban) are the ones an
  operator most needs to inspect, so readability is not limited to declared
  tables. In an adopted database this includes Laravel's inert framework
  tables;
- minus the columns a schema contract names in `secret_columns/0`:
  credentials, tokens, and opaque session state that no read surface may
  expose. Such a table is granted column by column, so `SELECT *` on it is
  refused and the console names the columns that may be read instead. Core
  User hides `users.password`, `users.remember_token`, and
  `password_reset_tokens.token`; Base Session hides `sessions.payload`;
- nothing else: no sequence privilege, no `CREATE`, and any other privilege
  the role holds in the prefix is revoked. Reconciliation is idempotent;
  re-run `mix bilimbi.migrate` after creating the role late or after a hand
  grant.

A contract that names a column its table does not have fails reconciliation
before any grant changes; a secret declared on a table the prefix does not
hold is reported, not refused, because a contract may know a table the
database has not migrated yet.

The protection runs one way only. A declared secret that is wrong is
reported, but a credential column nobody declared is silently readable
through the console: a new token, hash, or secret column is granted like
any other column, and nothing reminds its author. Declaring it in the
owner's `secret_columns/0` in the same change that adds the column is the
author's obligation (see the change checklist below).

**How a misconfigured console fails.** Before every run the executor asks
PostgreSQL, as the connected role, whether the connection could write
anything: superuser, role- or database-creation flags, `CREATE` on the
database or a schema, or any write privilege on any relation. While the
answer is not empty the console refuses to run and says why. A console
connected as the application's login therefore fails visibly and never
falls back to the read-write connection. The same holds for the grant step:
a missing role, or a console configured with the application's own login,
stops `mix bilimbi.migrate` with the instructions above after the migrations
have run.

**Upgrading an existing deployment.** Create the role, set
`CONSOLE_DATABASE_URL`, and run `mix bilimbi.migrate`. Until the role exists
the migrate task stops with instructions; until the connection string is set
production does not boot; until the grants are applied the console reports
"permission denied" on every table; and a console login that cannot connect
is reported on the console page. None of these is silent. In an adopted
Belimbing database the grant step must run as the role that owns the tables:
PostgreSQL only warns when another role grants or revokes, so after granting
the step confirms the console holds exactly its reads on every relation, and
refuses, naming the relation, when it does not, as it also does when a grant
to PUBLIC or to a role the console belongs to exposes more.

## Change checklist

When adding or changing persistent behavior:

1. identify the durable business owner;
2. classify every dependency using the four categories above;
3. declare the module edge before consuming a public contract;
4. place migrations, schema changes, tests, and contracts with the owner;
5. use a globally unique migration version and exact disposition;
6. update both sides of a cross-module contribution atomically;
7. update the schema contract, its live-data invariants, and its
   `secret_columns/0` when a new column holds a credential or token;
8. verify fresh migration and, when relevant, existing-schema adoption;
9. run `mix bilimbi.migrations`, focused tests, formatting, and the required
   repository checks; and
10. update this specification only when the database architecture changes,
    not merely to snapshot the current module graph.

## Related architecture

- [Composition model](./0010_composition-model.md)
- [ADR 0002: Compatible schema baselines and adoption](./decisions/0002-compatible-schema-baselines.md)
- [ADR 0003: Physical deep-module packages](./decisions/0003-physical-deep-module-packages.md)
- [ADR 0005: Laravel framework tables and job runtime](./decisions/0005-laravel-framework-tables-and-job-runtime.md)
- [ADR 0007: Contained Core User Administration integration read](./decisions/0007-core-user-administration-integration-read.md)
- [Base Database operational contract](../../apps/base/database/docs/README.md)
- [Core Compatibility operational contract](../../apps/core/compatibility/docs/README.md)
