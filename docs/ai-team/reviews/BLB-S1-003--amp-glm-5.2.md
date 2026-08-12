# BLB-S1-003 Review — amp/glm-5.2

**Reviewer:** amp/glm-5.2
**Role:** Independent architecture and compatibility reviewer (re-review)
**Reviewed Commit/Diff:** PR #9 (`feat/blb-s1-003-004-employee-company`, tip `efc678b`) — the published, reworked Employee module rebased onto post-#1 main
**Task Card:** [BLB-S1-003](../tasks/BLB-S1-003.md)
**Date:** 2026-08-12
**Prior review:** [BLB-S1-003--codex-gpt-5.md](./BLB-S1-003--codex-gpt-5.md) — `changes required`

## Verdict

`accept`

All three findings from the codex/gpt-5 review are addressed with focused
tests. The rework converts the platform orchestrator from an adoptable
convention into a protected, invariant-checked identity, and the system-type
bootstrap from a silent overwrite into a guarded, refuse-on-conflict
operation. Independent test runs confirm the implementation.

## Findings

### Critical

None.

### Major

None. Both Major findings from the prior review are resolved — see
"Prior-review finding check" below.

### Minor

1. **TOCTOU window in `ensure_system_types/0` is benign but untested.**
   `assert_system_type_bootstrap_safe/0`
   (`apps/core/employee/lib/employee.ex:344-359`) runs a select-then-insert
   with no transaction wrapping the check and the `insert_all`. A concurrent
   insert of a conflicting custom row between the two statements would bypass
   the guard and let `on_conflict: {:replace, …}` convert it. In practice
   this is a Mix-task bootstrap, not a hot concurrent path, so the risk is
   low. If it ever becomes callable from a LiveView or supervised task, wrap
   it in `Repo.transaction/1` or rely on a unique constraint to fail the
   insert. No change required for S1; noted for the record.

2. **`employee_types_code_unique` is a global unique on `code` alone**
   (`schema_contract.ex:69`, migration line 72). This means two companies
   cannot create custom types with the same code (e.g., both creating
   `"seasonal"`). The test "bootstraps global system types and isolates
   custom types by company" creates `"seasonal"` for company 73 and verifies
   company 74 cannot *see* it, but does not verify company 74 can *create*
   its own `"seasonal"`. The `reject_reserved_system_type_code/1` guard
   prevents collision with system codes, but cross-company custom-code
   collision would surface as a raw DB unique-violation, not a friendly
   changeset error. This matches the contract's declared index and the
   original review found no structural mismatch against Belimbing, so it is
   compatibility-preserving. I could not independently re-verify against
   Belimbing (the canonical source at `/home/kiat/repo/laravel/blb` is on a
   different machine). Flagging so a reviewer with Belimbing access can
   confirm the global unique is canonical, not a porting artefact.

## Prior-review finding check

### Major 1 — system-agent identity not protected → RESOLVED

The prior review identified four gaps. Each is addressed:

- **`update_employee/4` could change `employee_number`/`employee_type`** →
  `protect_platform_orchestrator_identity/2` (lines 308-330) rejects changes
  to `[:employee_number, :employee_type]` on orchestrator records, while
  allowing non-identity fields (`designation`, etc.) to update normally.
- **Any caller could pre-create an `agent` numbered `SYS-001`** →
  `reject_reserved_orchestrator_number/2` (lines 284-306) rejects `SYS-001`
  on create and on update of non-orchestrator records. A non-orchestrator
  employee cannot be renumbered to `SYS-001` either (the update clause
  falls through to the create clause when the existing record is not the
  orchestrator).
- **Primary-company transfer allowed a second orchestrator** →
  `resolve_platform_orchestrator/1` (lines 361-389) queries all `SYS-001`
  employees, splits them into orchestrator-matching (`agent` type) and
  non-matching, and returns `:invariant_violation` if the orchestrator's
  `company_id` does not match the current platform-operator company. It
  also returns `:invariant_violation` for multiple orchestrators, a
  non-`agent` `SYS-001` row, or any mixed state.
- **Deletion** → `delete_employee/4` (lines 121-122) rejects orchestrator
  deletion with `:invariant_violation`.

Tests covering all four:
`employee_test.exs:177-227` (identity protection: create rejected, update
rejected, non-identity update allowed, deletion rejected, ordinary
deletion succeeds); `:229-235` (conflicting `SYS-001` with `full_time`
type is refused, not adopted); `:237-251` (post-`transfer_primary_company`,
both `platform_orchestrator/0` and `ensure_platform_orchestrator/0` return
`:invariant_violation`).

### Major 2 — system-type bootstrap silently converts tenant custom rows → RESOLVED

`assert_system_type_bootstrap_safe/0` (lines 344-359) now queries for any
`employee_types` row whose `code` is a reserved system code but whose
`is_system` is not `true` or whose `company_id` is not `nil`. If any such
row exists, `ensure_system_types/0` returns `{:error, :invariant_violation}`
before the `insert_all` runs. The `on_conflict: {:replace, …}` is still
present (line 152) but can now only fire on rows that are already
system + company-less — i.e., it refreshes mutable fields (`label`,
`updated_at`) on rows it owns, not on tenant data.

Additionally, `reject_reserved_system_type_code/1` (lines 332-342) prevents
creating custom types with reserved codes through the public API.

Test: `employee_test.exs:253-266` inserts a custom `agent` type for
company 73, asserts `ensure_system_types/0` returns
`:invariant_violation`, and asserts `create_employee_type` with code
`full_time` is rejected with a friendly changeset error.

### Minor 1 — `employment_start` omitted on orchestrator provisioning → RESOLVED

`insert_platform_orchestrator/1` (line 397) now sets
`employment_start: Date.utc_today()`. Test line 169 asserts
`orchestrator.employment_start == Date.utc_today()`.

## Acceptance-criteria check

- [x] Public contract — schemas and queries are private; `Summary`/`TypeSummary`
  read models are returned; `Scope` is required on every tenant-owned read/write.
- [x] Module/dependency boundaries — descriptor declares `core/employee`,
  `layer: :core`, `required: true`, deps `base/database`, `base/tenancy`,
  `core/company`. Employee validates department ownership through Company's
  public `department_belongs_to_company?/3`, not through Company's private
  schema or queries.
- [x] Belimbing schema/data compatibility — migration and schema contract
  agree on columns, types, nullability, defaults, indexes, FK names/actions.
  Cross-module `company_departments.head_id → employees.id` FK is owned by
  the Employee migration via raw SQL, matching Belimbing's convention. (The
  original codex/gpt-5 review verified this against Belimbing source; I
  re-verified contract-vs-migration consistency but could not re-verify
  against Belimbing directly — different machine.)
- [x] Tenant, authorization, and soft-delete behavior — `Scope` pattern-match
  on every public function; cross-tenant reads return `:company_not_found` or
  `:not_found`; `employees` and `employee_types` are hard-delete (no
  `deleted_at`), matching the inventory §4.3.
- [x] Failure paths and operational observability — tagged errors
  (`:company_not_found`, `:employee_not_found`, `:not_provisioned`,
  `:invariant_violation`); DB constraint violations are normalized into
  changeset errors via `*_constraint` helpers.
- [x] Focused tests and documentation — 11 tests covering CRUD, tenant
  boundaries, orchestrator identity protection, collision refusal,
  transfer invariant, system-type bootstrap safety, type isolation,
  addressable identity, and scope enforcement. Module docs and `docs/README.md`
  present.
- [x] No unrelated or unclaimed changes — diff is Employee module + Company
  department seam + task-card/m mailbox updates only.

## Validation independently performed

- Read the full PR #9 diff: `employee.ex` (442 lines), `schema.ex`,
  `schema_contract.ex`, `employee_type.ex`, `summary.ex`, `type_summary.ex`,
  migration, descriptor, `company.ex` (department API), `department.ex`,
  both test files, both test fixtures.
- Cross-referenced every codex/gpt-5 finding against the reworked code and
  the new tests.
- `cd apps/core/employee && mix test` — **11 passed**.
- `cd apps/core/employee && mix format --check-formatted` — **exit 0**.
- Verified `department_belongs_to_company?/3` delegates to `get_company/2`
  (which uses `Tenancy.scope_query/2`), so soft-deleted companies are
  rejected before the department existence check.

## Follow-up tasks suggested

- Shared integration (BLB-S1-009) must register Employee's migration and
  schema contract in Compatibility, make `company_departments_head_id_foreign`
  required in the Company contract once Employee is installed, and replay a
  fresh schema. Already recorded on BLB-S1-009.
- Route `ensure_system_types/0` and `ensure_platform_orchestrator/0` through
  the planned production-seed ledger (BLB-S1-008) rather than leaving them
  as standalone Mix tasks. Already noted in the BLB-S1-003 card and the
  BLB-S1-001 review.
