# Base Database

The normative platform-wide database rules live in
[Bilimbi Database Architecture](../../../../docs/architecture/database.md).
This module document describes Base Database's owned implementation and
operational contracts; it does not define a second database architecture.

`apps/base/database/` is the complete physical boundary for the required
`base/database` module. It owns the shared Ecto Repo, compatible JSON type, and
schema-verification machinery used by higher modules.

`Bilimbi.Base.Repo` is intentionally the platform-wide public name for the one
shared Repo. It is the documented exception to the module's primary
`Bilimbi.Base.Database` namespace; physical ownership remains entirely inside
this package. Database also owns the shared SQL sandbox case used by module
tests and direct tests for schema verification.

The module owns no business tables or migrations. Higher modules ship their
own migrations and the platform executes all installed migration paths through
`Bilimbi.Base.Repo` and the shared `bilimbi_schema_migrations` ledger.

## Operator SQL console

`Bilimbi.Base.Database.QueryExecutor` runs the operator SQL console's SQL
through `Bilimbi.Base.Database.ConsoleRepo`, this module's second Ecto Repo,
which connects as a PostgreSQL role holding `SELECT` and nothing else. The
platform rules, the role's provisioning, what it may read, and how a
misconfigured console fails are in the architecture document's "Operator SQL
console" section; this section covers the implementation.

- `ConsoleRepo` is configured per environment beside `Bilimbi.Base.Repo`
  (`config/dev.exs`, `config/test.exs`, `CONSOLE_DATABASE_URL` in
  `config/runtime.exs`). It is `read_only: true` and is never in
  `ecto_repos`: it owns no storage and runs no migrations.
- `ConsoleAccess.reconcile/2` grants the role `SELECT` on every table in the
  prefix minus the installed contracts' `secret_columns/0` and revokes every
  other privilege it holds there, inside one transaction through the
  application's Repo. `mix bilimbi.migrate` calls it
  through `Bilimbi.Base.Database.reconcile_console_access/2`; a failure is
  turned into operator instructions by `ConsoleAccess.explain/1`.
- A schema contract declares the columns the console must never read in the
  optional `secret_columns/0` callback of
  `Bilimbi.Base.Database.SchemaContract`, keyed by owned table name.
- `ConsoleAccess.held_write_privileges/1` is the executor's per-run proof:
  it asks PostgreSQL, as the connected role, for every way the connection
  could write, and the executor refuses to run while the list is not empty.
- The console sees only committed state. Its test connection is not
  sandboxed, so a test that needs the console to read something creates it
  with `Ecto.Adapters.SQL.Sandbox.unboxed_run/2` and drops it afterwards;
  `test/console_access_test.exs` and `test/query_executor_test.exs` show
  the shape.

## Production seeds

Production reference data runs separately from structural migrations through
`Bilimbi.Base.Database.run_production_seeds/2`. The first run creates the
Bilimbi-owned `bilimbi_production_seeds` operational ledger in the selected
database prefix. Existing Belimbing databases keep their Laravel
`base_database_seeders` table unchanged; Bilimbi never adopts PHP class names
as seed identity and never reads, updates, renames, or drops that table.

Adoption therefore does **not** import Laravel completion state. A Belimbing
database whose PHP seeders already ran still starts with an empty Bilimbi
ledger, and the next `mix bilimbi.seeds.run` will invoke every registered
Bilimbi seed. That is intentional: PHP FQCNs are not Bilimbi seed IDs. Every
production callback must be idempotent (or safely resumable) so adoption
re-runs cannot duplicate or corrupt reference data.

The operational ledger is deliberately initialized by this runner rather than
contributed to the compatibility-baseline migration set. Existing Belimbing
databases do not contain this Bilimbi-owned table, while schema adoption records
every installed baseline migration without executing its DDL. Treating the
ledger as a required compatibility table would therefore either block adoption
or mark its creation migration complete while leaving the table absent. The
runner serializes first-use initialization under its per-prefix advisory lock.
After create-if-missing, the runner verifies the ledger column types,
nullability, precision and defaults, its allowed-status constraint, and its
required indexes against the expected shape and fails closed on drift; it does
not use this path to alter or conceal drift in canonical business tables.

Owning modules implement
`Bilimbi.Base.Database.ProductionSeedProvider` and explicitly register the
provider as `:bilimbi_production_seed_provider` in their own OTP application
environment. A provider builds definitions with
`Bilimbi.Base.Database.production_seed!/4`, which combines the installed
module's stable descriptor ID and resolved order with a local seed ID. Seed
dependencies use those full logical IDs. The runner validates the graph and
orders unrelated seeds by module order and logical ID.

Run every installed production provider with:

```console
mix bilimbi.seeds.run
```

An operator may add an already-compiled provider explicitly:

```console
mix bilimbi.seeds.run --provider Bilimbi.Core.Employee.ProductionSeeds
```

Explicit providers must implement `ProductionSeedProvider`, load from an
installed Bilimbi module OTP app, and emit seeds whose `module_id` matches
that module. Weak duck-typed modules are rejected. The explicit provider is
added to the normally discovered queue; if one of its seeds depends on another
unregistered provider, pass that provider explicitly as well. A missing
dependency fails graph validation before the ledger or callback data changes.
Each attempt is recorded as `running`, then `completed`, `failed`, or
`skipped`. Completed and skipped seeds are not invoked again. Failed seeds are
retryable, and rows left `running` by an interrupted process are marked failed
and retried on the next run. The runner holds a PostgreSQL advisory lock per
database prefix so two operators cannot execute the same production queue
concurrently. Listing execution state takes the same lock, including first-use
ledger creation.

Run results describe what happened in that invocation: an already-completed
seed returns `status: :skipped` because its callback was not invoked, while
`list_production_seed_runs/1` continues to report its durable ledger status as
`:completed`. A callback that returns `:skipped` records that terminal ledger
status and also reports `:skipped` for the invocation.

Before invoking any callback, the runner validates the installed workspace
through `Bilimbi.Base.ModuleRegistry` and verifies that every seed's module ID
and resolved order match that approved graph. Stale metadata from a different
workspace build is rejected before the ledger or reference data is touched.

Callbacks own the atomicity and idempotency of their reference-data writes.
The ledger makes completed callbacks at-most-once from the runner's point of
view, but it does not wrap arbitrary callbacks in one database transaction:
large imports and callbacks coordinating external resources may need their own
transaction boundaries. A retryable callback must therefore roll back partial
database work or safely resume/reapply it before returning `{:error, reason}`
or raising.

Development, demonstration, and test fixtures are intentionally outside this
provider contract and are never discovered by `mix bilimbi.seeds.run`.
