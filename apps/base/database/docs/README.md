# Base Database

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
After create-if-missing, the runner verifies the ledger column nullability/types
and required indexes against the expected shape and fails closed on drift; it
does not use this path to alter or conceal drift in canonical business tables.

Owning modules implement
`Bilimbi.Base.Database.ProductionSeedProvider` and explicitly register the
provider as `:bilimbi_production_seed_provider` in their own OTP application
environment. A provider builds definitions with
`Bilimbi.Base.Database.production_seed!/4`, which combines the installed
module's stable descriptor ID and resolved order with a local seed ID. Seed
dependencies use those full logical IDs. The runner validates the graph and
orders unrelated seeds by module order and logical ID.

Run every installed production provider with:

```powershell
mix bilimbi.seeds.run
```

An operator may add an already-compiled provider explicitly:

```powershell
mix bilimbi.seeds.run --provider Bilimbi.Core.Employee.ProductionSeeds
```

Explicit providers must implement `ProductionSeedProvider`, load from an
installed Bilimbi module OTP app, and emit seeds whose `module_id` matches
that module. Weak duck-typed modules are rejected.
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
