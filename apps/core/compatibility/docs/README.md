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
