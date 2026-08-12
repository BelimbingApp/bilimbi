# BLB-S1-004 Review — amp/glm-5.2

**Reviewer:** amp/glm-5.2
**Role:** Independent architecture and compatibility reviewer (re-review)
**Reviewed Commit/Diff:** PR #9 (`feat/blb-s1-003-004-employee-company`, tip `efc678b`) — the published, reworked Company department seam rebased onto post-#1 main
**Task Card:** [BLB-S1-004](../tasks/BLB-S1-004.md)
**Date:** 2026-08-12
**Prior review:** [BLB-S1-004--codex-gpt-5.md](./BLB-S1-004--codex-gpt-5.md) — `accept with follow-up`

## Verdict

`accept`

The prior review's sole follow-up — a direct assertion that
`department_belongs_to_company?/3` rejects a department whose owning
company is soft-deleted — is now present and tested. No new findings.

## Findings

### Critical

None.

### Major

None.

### Minor

None.

## Prior-review finding check

### Minor 1 — no soft-deleted-company department assertion → RESOLVED

The prior review noted that `company_test.exs` covered matching,
cross-company, cross-tenant, and invalid department IDs, but did not
directly prove the API rejects a department whose owning company is
soft-deleted.

`company_test.exs:57-66` now inserts a company with
`deleted_at: ~N[2026-08-11 12:00:00]`, attaches a department to it, and
asserts:

```elixir
refute Company.department_belongs_to_company?(owner, soft_deleted_company_id, 103)
```

This works because `department_belongs_to_company?/3`
(`apps/core/company/lib/company.ex:84`) delegates to `get_company/2`,
which uses `Tenancy.scope_query/2` — the tenant-scoped query that filters
out soft-deleted companies. A soft-deleted company returns
`{:error, :not_found}`, and the `else` clause returns `false` before the
department existence check runs.

## Acceptance-criteria check

- [x] Public contract — `department_belongs_to_company?/3` is the only new
  public function; it returns a boolean and exposes no Company schema or
  query to Employee. The `Department` schema (`apps/core/company/lib/company/department.ex`)
  is private (`@moduledoc false`).
- [x] Module/dependency boundaries — Employee validates department ownership
  through this public API, never reaching into Company's private queries or
  schema. The canonical `company_departments.head_id` FK is physically owned
  by Employee's migration, not Company's.
- [x] Belimbing schema/data compatibility — the private `Department` schema
  maps `company_departments` columns; the original review verified this
  against Belimbing and found no mismatch.
- [x] Tenant, authorization, and soft-delete behavior — scope-enforced,
  soft-deleted-company rejection now directly tested.
- [x] Failure paths and operational observability — fails closed (`false`)
  for not-found company, soft-deleted company, cross-tenant, and invalid IDs.
- [x] Focused tests and documentation — 17 tests including the new
  soft-deleted-company assertion.
- [x] No unrelated or unclaimed changes — Company diff is the department
  schema + collaboration API + test fixture + test only.

## Validation independently performed

- Read `company.ex:81-95` (`department_belongs_to_company?/3`) and confirmed
  it delegates to `get_company/2` → `Tenancy.scope_query/2`, which filters
  soft-deleted companies.
- Read `company_test.exs:40-67` — the department-ownership test including
  the new soft-deleted-company assertion.
- `cd apps/core/company && mix test` — **17 passed** (the logged
  `platform operator identity is invalid` line is the expected
  soft-deleted-company invariant test, not a failure).
- `cd apps/core/company && mix format --check-formatted` — **exit 0**.

## Follow-up tasks suggested

- During shared integration (BLB-S1-009), change Company's
  `company_departments_head_id_foreign` contract entry from optional to
  required once Employee is registered. Already recorded on the BLB-S1-004
  card and the prior review.
