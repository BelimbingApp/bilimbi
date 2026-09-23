# Base Audit

ADR 0013 is the contract. `Bilimbi.Base.Audit.MutationCapture`'s moduledoc is the policy. Do not copy either here.

Bulk writes are captured. `insert_all`, `update_all`, and `delete_all` go through the same seam as struct writes. Do not treat a query write as invisible.

A missing actor is recorded as guest (`Bilimbi.Base.Audit.Context.get/0` returns `actor_type` `"guest"` and `actor_id` `0`). Do not skip the write, and do not invent an actor, to avoid that row.

Secrets and opaque blobs, including a session `payload`, are redacted in `@redacted_fields` on `MutationCapture`. Do not redact at the call site. The change is recorded; the value is not.

An instant inside a diff includes seconds. `MutationDiff.diff_value/1` passes `precision={:second}` so two edits in one minute stay distinct. The history entry's own clock can stay at minute precision.

Silencing capture is not done from this folder. `Bilimbi.Base.Database.WriteCapture.without_capture/1` needs a written, table-level reason. See `apps/base/database/AGENTS.md`.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
