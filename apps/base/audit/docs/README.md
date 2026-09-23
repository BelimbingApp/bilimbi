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

## Database console commands

`Bilimbi.Base.Audit.ConsoleCapture` implements Base Database's
`ConsoleCapture` seam (`config :bilimbi_base_database, :console_capture`),
so every command handed to `Bilimbi.Base.Database.execute_readonly/3` is one
`base_audit_actions` row whatever its outcome: `database_query.executed`
with the matched row count, `database_query.refused` with the guard
(`operator`, `empty`, `statement`, `keyword`, or `read_only_transaction`)
and its message, or `database_query.failed` with the database's error
message. The actor pair, role, company, tenant, `impersonator_id`,
`ip_address`, `url`, `user_agent`, and `trace_id` come from
`Bilimbi.Base.Audit.Context`; an absent context records the guest default.
Result rows never reach the record.

The SQL is stored **as typed**, bounded by `Bilimbi.Base.Audit.PayloadText`
(the same 2000-character cut, with marker, that captured mutation values
get, with each NUL character stored as `␀` because PostgreSQL `jsonb`
cannot hold one). Nothing redacts by content: a secret pasted into a query is recorded.
Rows are `is_retained: false` like every other recorded action; nothing in
Bilimbi prunes `base_audit_actions`, retained or not, so the flag only
marks a row and drives the "Retained" filter. The actions screen presents a
console row with the query name, the text, and the outcome, lists them
under the "SQL console" family (value `database`, distinct from the
"Console" family of `console.command`), and counts refused and failed
commands as failures.

## Audit log screens

`/audit/actions` and `/audit/mutations` are the module's own LiveViews under
`lib/audit/web/`. Both page through Base UI's `<.pagination>`: the summary,
numbered pages with disabled ends, and the rows-per-page selector are the
component's, so the single-page rule (count and selector shown, navigation
absent) has one owner. The selector posts `filters[perPage]` into the same
`filter` event as the toolbar, and a key the posting form did not carry keeps
its current value; the URL keeps each screen's own `page_size` key so
bookmarked links from before the swap still resolve. The retain toggle names
its glyphs through the icon registry as `retain` and `retained`, Belimbing's
outline and solid bookmark.
