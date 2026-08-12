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

Each attempt is recorded as `running`, then `completed`, `failed`, or
`skipped`. Completed and skipped seeds are not invoked again. Failed seeds are
retryable, and rows left `running` by an interrupted process are marked failed
and retried on the next run. The runner holds a PostgreSQL advisory lock per
database prefix so two operators cannot execute the same production queue
concurrently.

Development, demonstration, and test fixtures are intentionally outside this
provider contract and are never discovered by `mix bilimbi.seeds.run`.
