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
