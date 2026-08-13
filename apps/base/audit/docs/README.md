# Base Audit

`apps/base/audit/` is the complete physical boundary for the required
`base/audit` deep module. Its public API is `Bilimbi.Base.Audit`.

The module records durable mutation and action facts. Rows outlive their
actors and subjects: `company_id`, `tenant_id`, and the actor pair have
**no foreign keys**. Recording takes a `Bilimbi.Base.Tenancy.Scope` or
`:unscoped`; it never reads `tenant_id` from the attributes map. Unscoped
rows stay null. Numeric ID 1 has no runtime meaning. Actor types are
`user`, `agent`, `guest`, `console`, `scheduler`, and `queue`.

Payloads are PostgreSQL `jsonb`. `ip_address` is `inet`, matching Laravel 13
`ipAddress()` on PostgreSQL. There are no `created_at` / `updated_at` /
`deleted_at` columns; event time is `occurred_at` only.

Callers receive `Bilimbi.Base.Audit.Mutation` and
`Bilimbi.Base.Audit.Action`, never the private Ecto schemas.

This change registers `base/audit` on `core/compatibility` because CI check
013 requires the coordinator's runtime closure to include every migration
or schema-contract contributor. That descriptor edit is shared and must be
called out on issue #43; this package still does not hard-code coordinator
internals.
