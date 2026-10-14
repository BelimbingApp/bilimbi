# Base Audit

ADR 0013 is the contract. `Bilimbi.Base.Audit.MutationCapture`'s moduledoc is the policy. Do not copy either here.

Bulk writes are captured. `insert_all`, `update_all`, and `delete_all` go through the same seam as struct writes. Do not treat a query write as invisible.

A missing actor is recorded as unknown (`Bilimbi.Base.Audit.Context.get/0` returns `actor_type` `"unknown"` and `actor_id` `0`). Scoped records inherit the sealed actor; `Audit.with_scope/2` attributes repo writes. Do not invent a guest actor to hide absent context.

Secrets and opaque blobs, including a session `payload`, are redacted in `@redacted_fields` on `MutationCapture`; separately protected schema payloads declare `__audit_redacted_fields__/0`, which that same capture policy applies to struct and bulk writes. Do not redact at the call site. The change is recorded; the value is not.

An instant inside a diff includes seconds. `MutationDiff.diff_value/1` passes `precision={:second}` so two edits in one minute stay distinct. The history entry's own clock can stay at minute precision.

Tenant timeline indexes are optional in `SchemaContract`, not required for baseline adoption. Change their ordering in that contract and the Bilimbi-only migration together.

The mutations table shows `MutationDiff.summary/1` on each row. Field values render only while `Bilimbi.Base.Audit.Web.MutationDetails` is open. Do not call `MutationDiff.rows/1` for every row of that table.

Silencing capture is not done from this folder. `Bilimbi.Base.Database.WriteCapture.without_capture/1` needs a written, table-level reason. See `apps/base/database/AGENTS.md`.

Evidence rows are append-only; `Migrations.HardenAuditEvidence` owns the PostgreSQL guards and database recording clock. A retention change updates separate metadata through `toggle_retained/2`, which asks `Bilimbi.Base.Audit.Authorization`. The workspace wires that to Base Authz in `config/config.exs`. Do not add a `base/authz` dependency: Authz already depends on Audit, and discovery rejects the cycle. The actions screen's `can_manage` assign only shows the control.

A value of a field an operator restricted (`Bilimbi.Base.Authz.put_field_restriction/4`, reaching this module through the grid table's `record_types`) is taken out of every `Mutation` the read functions return, through `Bilimbi.Base.Audit.Authorization.withheld_fields/2`. A screen renders `Mutation.withheld` as `<.restricted>`; do not list field names here, and do not read `old_values` or `new_values` from a schema, which would skip that policy.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
