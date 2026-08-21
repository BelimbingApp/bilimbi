# 13. Repo-level audit mutation capture

Date: 2026-08-22

## Status

Proposed

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
canonical row records old values. Postgres triggers were rejected: they
cannot see the actor.

## Decision

**Repo-level capture, owned by Base Database (mechanism) and Base Audit
(policy), wired in workspace configuration.**

- `Bilimbi.Base.Database.WriteCapture` (Base Database) defines the
  behaviour — `after_write(action, changeset_or_struct, result)` — the
  process-scoped kill switch `without_capture/1`, and the dispatcher the
  repo calls after each **successful** struct write. The capture module is
  read from `:bilimbi_base_database, :write_capture` application
  configuration; unset means no capture. Base Database gains **no**
  dependency edge: it defines a seam and calls whatever the workspace
  configured, the same wiring shape as Core User's `:pubsub_server`.
- `Bilimbi.Base.Repo` overrides the seven struct write functions via
  `defoverridable Ecto.Repo` + `super`, dispatching to `WriteCapture` on
  success. Query-based bulk writes (`update_all`, `delete_all`,
  `insert_all`) and raw SQL are **not** captured — Eloquent model events do
  not fire for query-builder bulk writes either, so this is canonical
  parity, not a gap; a bulk operation that needs audit records one
  explicitly (the data-operation ledger pattern).
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
  `api_key`, `token`) rendered as `[redacted]`, and string truncation at
  2000 characters with an explicit truncation marker.
- **Recursion and exclusion**: capture always skips Base Audit's own
  schemas; further schemas opt out via `:bilimbi_base_audit,
  :exclude_schemas` configuration — the port of `audit.exclude_models`,
  with the same justification discipline (a comment per entry).
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

- Every struct write through the shared Repo is audited by default; a new
  module gets a complete audit trail by existing, and silence becomes an
  explicit, greppable opt-out instead of a forgotten opt-in.
- The three existing `Audit.record_mutation` call sites remain valid for
  semantic rows the capture cannot infer; capture writes `source:
  "listener"` rows, keeping the two origins distinguishable, as in the
  source.
- The runtime wiring crosses the module graph by configuration, not by
  compile-time reference; the graph gate keeps holding for code, and this
  ADR is the record for the one sanctioned config edge.
- Multi/`insert_or_update` flow through the overridden functions;
  anything bypassing the repo's struct API bypasses capture, and the
  write-session test in `apps/web` pins the guarantee for real domain
  writes (Employee, Company) so a regression in the seam fails loudly.
- Subject expansion (`getAuditSubject`/`getAuditSubjectEntries`) is
  deferred: capture leaves the subject columns null until a schema needs
  them, at which point optional callbacks port the source's
  `method_exists` probes.
