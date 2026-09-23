# 13. Repo-level audit mutation capture

Date: 2026-08-22

## Status

Accepted

Amended 2026-09-23 (#785): bulk writes are captured. The original decision
excluded them and the Consequences below record what changed.

## Context

Belimbing audits **all** model mutations globally: a wildcard Eloquent
listener (`app/Base/Audit/Listeners/MutationListener.php` at pin `e70b4d33`)
captures create/update/delete on every model, opt-**out** via config and
model properties, with a `withoutAuditing` kill switch, field
redaction/truncation strategies, and buffered writes into the compatible
`base_audit_mutations` table.

Bilimbi ported audit as an opt-**in** API. `Audit.record_mutation/2` has
three callers; every Employee, Company, and Address write leaves the audit
tables empty (#630, verified empirically). An admin platform whose audit
trail silently misses most writes is dishonest.

Ecto has no global model events, so the capture seam must be designed.
Candidates considered:

1. **Repo-level capture** — wrap the shared `Bilimbi.Base.Repo` write
   functions; modules opt out explicitly, like the source.
2. Per-module changeset/write-path instrumentation via a shared helper —
   honest but opt-in, which is exactly the shape that already drifted to
   three callers.
3. Explicit `Audit.record_mutation` calls in every domain write — maximal
   ceremony, no seam, and the same drift guarantee as 2.

Within option 1, the interception point matters. Ecto generates the repo
functions non-overridable by default, but `defoverridable Ecto.Repo` after
`use Ecto.Repo` marks every behaviour callback overridable, so the repo
module itself can wrap `insert/2`, `update/2`, `delete/2`, their `!`
variants, and `insert_or_update/2` around `super`. The adapter layer was
rejected: adapter callbacks see changed fields but not originals, and the
canonical row records old values. Postgres triggers were rejected; #785
built and measured them, and the accurate reason is recorded there and in
the Decision below — not that they cannot see the actor, but that they can
only see one the application declares inside the same transaction, which
is the same cooperation this seam already needs, bought at a higher price
and with a silent-falsehood failure mode.

## Decision

**Repo-level capture, owned by Base Database (mechanism) and Base Audit
(policy), wired in workspace configuration.**

- `Bilimbi.Base.Database.WriteCapture` (Base Database) defines the
  behaviour — `after_write(action, changeset_or_struct, result)`,
  `after_bulk_write(schema, changes)`, and `capture_schema?(schema)` — the
  process-scoped kill switch `without_capture/1`, and the dispatchers the
  repo calls after each **successful** write. The capture module is
  read from `:bilimbi_base_database, :write_capture` application
  configuration; unset means no capture. Base Database gains **no**
  dependency edge: it defines a seam and calls whatever the workspace
  configured, the same wiring shape as Core User's `:pubsub_server`.
- `Bilimbi.Base.Repo` overrides the eight struct write functions
  (`insert`, `update`, `delete`, `insert_or_update` and their `!` variants)
  **and the three query-based bulk writes** (`insert_all`, `update_all`,
  `delete_all`) via `defoverridable Ecto.Repo` + `super`, dispatching to
  `WriteCapture` on success.
- **Bulk capture** (#785). A bulk write hands the repo a query rather than
  a changeset, so `Bilimbi.Base.Database.BulkCapture` gathers the rows the
  statement affected and dispatches them as
  `after_bulk_write(schema, changes)`, one `{action, old_row, new_row}` per
  row. What that costs differs by operation: `insert_all` reads the new
  rows from `RETURNING`; for `delete_all` the returned rows **are** the old
  values; only `update_all` needs anything extra, one `SELECT` of the
  originals before the statement. The caller's result is preserved exactly
  — the added `select` and `returning: true` never reach them. Capture
  writes one `insert_all` per 1,000 affected rows, never one insert per
  row: a row-at-a-time capture measured about 33x worse on a large batch,
  because the cost is an Elixir round trip, not database work, and the
  chunk keeps each statement below PostgreSQL's 65,535 bind-parameter
  ceiling, so a large bulk write is never left unaudited. `insert_all`
  dumps but does not cast, so each row is shaped by the same
  `MutationSchema.changeset/2` the struct path uses and applied before
  batching, which is what casts `ip_address`.
- **Belimbing parity is deliberately departed from here.** Eloquent model
  events do not fire for query-builder writes, and the original decision
  read that as canonical parity rather than a gap. It was a gap: granting
  or revoking a role or a capability from the product UI left no audit row
  at all, and 39 bulk-write call sites reached this path. Parity with the
  source is not a reason to leave a hole in an audit trail.
- **Upserts.** `insert_all` with a replacing `:on_conflict` returns the row
  whether it inserted or replaced. When the conflict target names fields,
  the rows it could collide with are read first and a returned row already
  in that set is recorded as the update it was. When the target is an
  `:unsafe_fragment` index predicate, the write is **not** captured, logged
  and counted on the capture-failure event: a record calling a replacement
  a creation would be a false one, and a missing record is the lesser
  failure.
- **Raw SQL remains uncaptured as a mutation, and is kept empty of
  auditable writes rather than covered.** The database console is a
  developer tool that runs on the application's own connection, by
  decision: developers are trusted, and a console login of its own would
  restrict nothing worth restricting. Its transaction is genuinely
  read-only (#781), so a console write is refused by PostgreSQL itself,
  and every console command — succeeded, refused by a text guard or by
  the read-only transaction, or failed at the database — is recorded in
  the audit actions log through the `ConsoleCapture` seam in Base
  Database, with the actor, impersonator, client address, agent, and page
  the web edge put in the audit context. The record, not a restriction,
  is the control: it exists to tell a developer's own work from a command
  run through their stolen or hijacked session. The write block serves
  the same purpose — because the console cannot write, an intruder in a
  developer's session cannot use it to delete or edit the very audit
  records that would reveal them. Elsewhere, raw-SQL DML is confined to
  the lifecycle modules that need it (the production-seed ledger and the
  compatibility cutover) by review convention, not by a mechanical guard.
  A real mechanical control for the rest of the codebase is follow-up
  work.
- **Postgres triggers were built, measured and rejected** (#785). They
  work, and they are the only mechanism that sees a write the application
  did not make. They were rejected because they do not remove the
  application's obligation to declare the actor — they relocate it into a
  transaction-local setting many call sites are not positioned to provide —
  and when that obligation is missed the trail does not go quiet, it
  **lies**, recording `guest` where an administrator acted. They also
  cannot see `without_auditing/1`, would duplicate the redaction policy in
  SQL, double-record against this capture, and cost the same: auditing the
  largest bulk write in the codebase added about 3.5s either way, because
  the cost is writing the audit rows, not intercepting the statement.
- **Neither mechanism defends against someone holding database
  credentials.** A direct connection bypasses an application-layer capture
  entirely, and a superuser can disable a trigger. The control for that is
  credential custody and connection policy, not audit design.
- `Bilimbi.Base.Audit.MutationCapture` (Base Audit) implements the
  behaviour and owns the canonical row shape (§5 of the audit port):
  actor columns from the per-process `Bilimbi.Base.Audit.Context` (set at
  the web edge in the same lifecycle as locale; `guest`/`0` fallback when
  absent, exactly the source's `PrincipalType::GUEST` default), `tenant_id`
  from the mutated row's own `tenant_id` attribute first and the context
  second (the source's ground-truth order), `auditable_type` defaulting to
  the Ecto schema module name with an optional `__audit_auditable_type__/0`
  schema callback for canonical morph strings, changed-fields-only diffs
  for updates with originals, full attributes for create/delete, global
  redaction (`password`, `password_hash`, `remember_token`, `secret`,
  `api_key`, `token`, and `payload` — the durable session's opaque Laravel
  blob) rendered as `[redacted]`, and string truncation at
  2000 characters with an explicit truncation marker.
- **Recursion and exclusion**: capture always skips Base Audit's own
  schemas; further schemas opt out via `:bilimbi_base_audit,
  :exclude_schemas` configuration — the port of `audit.exclude_models`,
  with the same justification discipline (a comment per entry). A schema
  belongs on that list only when *nothing* written to it is an actor's
  business decision. Where one table holds both — sessions (the expiry
  sweep), employee types — the machine-only call site wraps itself in
  `WriteCapture.without_capture/1` and says why there, so the actor's
  writes to the same table stay captured. These two controls are the whole
  flooding answer; there is no third concept.
- **`withoutAuditing` semantics**: `Audit.without_auditing/1` delegates to
  `WriteCapture.without_capture/1` — a process flag, restored by `after`,
  exactly the source's static-flag try/finally. Production seeding and
  schema lifecycle tasks run under it.
- **Capture never fails the business write.** A raise inside capture is
  rescued, logged (redacted — never row values), and counted via telemetry
  `[:bilimbi, :base, :audit, :capture_failure]`. The source buffered writes
  and could lose them silently; Bilimbi keeps the write-path guarantee but
  makes the loss observable.
- **Transactionality**: capture runs synchronously in the caller's process,
  inside any open transaction. A rolled-back business write rolls its audit
  row back with it — strictly stronger than the source's request-end buffer,
  which could persist mutations whose transaction died. Inside a caller's transaction the audit
  row is written under a **savepoint** (DBConnection's `mode: :savepoint`;
  Ecto's nested transactions flatten and would abort the caller), so a
  capture failure rolls back only to its savepoint and can never abort the
  business transaction. A missing `base_audit_mutations` table is the pre-canonical
  state (fixture-built test databases, fresh checkouts before migration) and
  is silently not captured — the Locale precedent for pre-canonical Settings.

## Consequences

- Every write through the shared Repo is audited by default; a new module
  gets a complete audit trail by existing, and silence becomes an
  explicit, greppable opt-out instead of a forgotten opt-in.
- The three existing `Audit.record_mutation` call sites remain valid for
  semantic rows the capture cannot infer; capture writes `source:
  "listener"` rows, keeping the two origins distinguishable, as in the
  source.
- The runtime wiring crosses the module graph by configuration, not by
  compile-time reference; the graph gate keeps holding for code, and this
  ADR is the record for the one sanctioned config edge.
- Multi/`insert_or_update` flow through the overridden functions. The
  residual boundary is now the repo itself: anything bypassing
  `Bilimbi.Base.Repo` entirely bypasses capture, which is why raw-SQL DML
  is confined to the lifecycle modules by review convention. The write-session test in
  `apps/web` pins the guarantee for real domain writes (Employee, Company)
  and, since #785, for a real permission change driven through the User
  detail screen — the regression that would have caught the bulk-write gap
  in the first place.
- A bulk write on a captured schema now costs one extra statement at most
  (`update_all`'s pre-read), and `RETURNING` on the others. Nothing is read
  for an excluded schema: the repo asks the capture module before it
  gathers anything. The realistic audited bulk write in this codebase —
  replacing a role's forty capabilities — measured 13ms including that
  pre-read.
- The `update_all` pre-read and the update are two statements, so under
  `READ COMMITTED` a concurrent write between them can leave a row with no
  known original. Such a row records the full new row rather than a diff
  against a guess. PostgreSQL 18's `RETURNING WITH (OLD AS ...)` would
  close the window entirely; Ecto's query builder cannot express it yet,
  and reaching it through hand-written SQL would bypass the seam this
  decision strengthens.
- Subject expansion (`getAuditSubject`/`getAuditSubjectEntries`) is
  deferred: capture leaves the subject columns null until a schema needs
  them, at which point optional callbacks port the source's
  `method_exists` probes.
