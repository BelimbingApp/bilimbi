# BLB-S1-004 Review — codex/gpt-5

**Reviewer:** codex/gpt-5
**Role:** Independent architecture and compatibility reviewer
**Reviewed Commit/Diff:** Worktree changes above baseline `54b50b0`, limited to `apps/core/company/**`
**Task Card:** [BLB-S1-004](../tasks/BLB-S1-004.md)
**Date:** 2026-08-12

## Verdict

`accept with follow-up`

No blocking finding exists in BLB-S1-004.

## Findings

### Critical

None.

### Major

None.

### Minor

1. `apps/core/company/test/company_test.exs:39-52` covers matching, cross-company, cross-tenant, and invalid department IDs, but does not directly prove that the new collaboration API rejects a department whose owning company is soft-deleted. The implementation currently fails closed because it delegates to `get_company/2`; add that focused assertion so the live-company part of the boundary cannot regress independently.

## Acceptance-criteria check

- [x] Public contract
- [x] Module/dependency boundaries
- [x] Belimbing schema/data compatibility
- [x] Tenant, authorization, and soft-delete behavior where relevant
- [x] Failure paths and operational observability
- [x] Focused tests and documentation
- [x] No unrelated or unclaimed changes

## Validation independently performed

- Read canonical Company department migrations/models and Employee creation validation in Belimbing commit `e70b4d33c0b10790e681f4c2b5095d85a53bc918`.
- Confirmed the private Ecto schema maps the canonical `company_departments` columns and the public API validates ownership without exposing Company's schema or queries to Employee.
- Confirmed Employee, rather than Company, physically owns the later `company_departments.head_id -> employees.id` migration, matching Belimbing's cross-module FK convention.
- Ran `mix test` from `apps/core/company`: 13 passed.
- Ran `mix format --check-formatted` from `apps/core/company`: passed.

## Follow-up tasks suggested

- During shared integration, change Company's currently optional `company_departments_head_id_foreign` contract to required only after Compatibility declares/loads Employee, as the handoff specifies.
