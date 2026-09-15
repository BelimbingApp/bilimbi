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

## Impersonation

`actor_id` always names the account an action was performed as. When an
operator acts while impersonating another user, the Bilimbi-only
`impersonator_id` column on both tables names the operator, so one row
recovers both identities. It is nullable, has no foreign key, and carries a
partial index. Captured mutations take it from `Bilimbi.Base.Audit.Context`;
explicit records inherit it from the same context unless they name the key.
The web edge also records retained `impersonation.started` and
`impersonation.stopped` actions with the operator as the actor, mirroring
Belimbing's `ImpersonationManager`.

Belimbing's pinned schema has no such column (its semantic recorder only
carries an `impersonator_id` payload key, and its mutation listener nothing),
so the column and index are declared as an optional group in the schema
contract: an adopted database verifies before and after the Bilimbi-only
migration `20260914090000` runs.

This change registers `base/audit` on `core/compatibility` because CI check
013 requires the coordinator's runtime closure to include every migration
or schema-contract contributor. That descriptor edit is shared and must be
called out on issue #43; this package still does not hard-code coordinator
internals.
