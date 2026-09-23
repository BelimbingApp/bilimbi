# Base Database

`without_capture/1` turns audit capture off in this process, bulk writes included. Call it only with a written reason for that table, at a machine-only site whose other writes stay captured. Silence for a whole schema is `:bilimbi_base_audit, :exclude_schemas` in `config/config.exs`. There is no third mechanism. The comment on `without_capture/1` is the check before using it.

A test of a security or database boundary makes PostgreSQL refuse. For the SQL console that control is the `READ ONLY` transaction `Bilimbi.Base.Database.QueryExecutor` runs every command in. Do not prove the boundary by reading source.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
