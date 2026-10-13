# Base Audit

`apps/base/audit/` is the complete physical boundary for the required
`base/audit` deep module. Its public API is `Bilimbi.Base.Audit`.

The module records durable mutation and action facts. Rows outlive their
actors and subjects: `company_id`, `tenant_id`, and the actor pair have
**no foreign keys**. Recording takes a `Bilimbi.Base.Tenancy.Scope` or
`:unscoped`; it never reads `tenant_id` from the attributes map. Unscoped
rows stay null. Numeric ID 1 has no runtime meaning. Actor types are
`user`, `agent`, `guest`, `console`, `scheduler`, `queue`, `system`, and `unknown`.

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

## System principals

A job that runs as a named system principal (ADR 0017) records `actor_type`
`"system"`, `actor_id` `0`, and the principal's name in the Bilimbi-only
`system_principal` column on both tables. Base Queue sets that context for the
job; captured mutations take it from `Bilimbi.Base.Audit.Context`, and explicit
records inherit it unless they name the key. A row with a principal must be a
`"system"` row, an anonymous system scope leaves the principal null. The column and its partial
index are a second optional group in the schema contract, added by the
Bilimbi-only migration `20260927090000`.

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
`Bilimbi.Base.Audit.Context`; an absent context explicitly records `unknown/0`.
Result rows never reach the record.

The SQL is stored **as typed**, bounded by `Bilimbi.Base.Audit.PayloadText`
(a 2000-character cut, with marker, with each NUL character stored as `␀` because PostgreSQL `jsonb`
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

## Timeline indexes

Each schema contract owns whether its timeline index is optional and which
order a present index must match, so a compatible Belimbing database can still
be adopted.

Recorded before/after measurements for the additive indexes: audit tenant
count 169 ms to 22.7 ms, audit page 100 189 ms to 19.5 ms, and Authz page
0.76 ms to 0.14 ms. These figures were supplied with the change, not
re-measured.

## Evidence hardening

Migration `20261013120000` leaves existing evidence and event times intact.
PostgreSQL rejects UPDATE, DELETE, and TRUNCATE on actions, mutations and
capture-failure evidence. The compatibility `is_retained` bit becomes an
immutable initial value; mutable bookmarks live in `base_audit_action_metadata`.
The existing facade and retained filter resolve that metadata transparently.

`recorded_at` is always stamped by PostgreSQL's `clock_timestamp()` in UTC,
regardless of a caller-supplied value. Historical rows have null recording time:
we cannot reconstruct when they were inserted. `occurred_at` remains the
caller's event time for imported or explicit facts; when absent, the database
sets it from recording time. Automatic capture uses database time only.

Direct `record_action/2` and `record_mutation/2` calls inherit identity from
Scope when attributes omit it. Explicit identity keys retain their contract.
Use `Audit.with_scope(scope, fun)` for repo writes outside the web edge: it
reads the sealed actor, including impersonation, and restores context. Base
Queue runs every job under it with the job's resumed scope (the delegated user
or the named system principal), and ordinary system jobs as actor `queue`. A
job the Schedule recurrence enqueued runs as actor `scheduler`. Seeds and mix tasks that write run
under `Audit.with_actor("system", fun)` (`"console"` for operator grants).
Only a write with no edge at all is `unknown/0`; an explicitly supplied guest
remains a guest. Mutation strings are stored in full, never truncated, with
NUL escaped as `␀`.

### Redacted fields

The change to a redacted field is recorded; its value is not, because an audit
log readable by many operators must not become a second copy of a credential.
Two sets are replaced with `[redacted]` in `old_values` and `new_values`:

- Globally, by field name on any captured schema: `password`, `password_hash`,
  `remember_token`, `secret`, `api_key`, `token`, and `payload`. `payload` is
  the durable session's opaque Laravel blob, which can hold a CSRF token or a
  password hash that no field name reveals.
- Per schema, through `__audit_redacted_fields__/0`: Integration exchanges,
  Agent API plans, and Agent Access devices and tokens declare their hashes.

A schema whose field is named `secret`, `token`, or `payload` but holds
non-sensitive data must use another field name; widening the audit record means
changing the list in `MutationCapture`, not working around it at a call site.

Capture failures create append-only `base_audit_capture_failures` diagnostics
under a savepoint, in the caller's transaction, and emit `capture_failure`
telemetry with a `durable` flag. Messages and row values are
never logged or stored in diagnostics. A rolled-back business transaction
also rolls back diagnostics. If the diagnostics store itself is unavailable,
telemetry reports `durable: false`; the default business write still succeeds.
`Audit.with_strict_capture(fun)` raises a value-safe `Database.CaptureError` on failure; wrap it in a Repo transaction
when the business write must roll back. Existing capture adapters may implement
the optional `capture_failure/3` callback without changing their existing API.
