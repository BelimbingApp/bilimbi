# BLB-S1-006 Review — codex/sol-high

**Reviewer:** codex/sol-high
**Role:** Independent compatibility reviewer
**Reviewed Commit/Diff:** PR #21 product head `effd002`; integrated state at
`origin/main` `56ef4c1` (including the PR #23 compatibility registration and
BLB-S1-009 closeout)
**Task Card:** [BLB-S1-006](../tasks/BLB-S1-006.md)
**Date:** 2026-08-13

## Verdict

`accept with follow-up`

The S1 User foundation satisfies its card and preserves the pinned Belimbing
schema and tenancy boundaries. The deferred tenant-wide read is a real Web/Auth
consumer gap, but it is explicitly out of this package's public contract and is
already tracked by BLB-S1-010; it does not require rework of the merged unit.

## Findings

### Critical

None.

### Major

None.

### Minor

None.

## Acceptance-criteria check

- [x] Public contract — `Bilimbi.Core.User` returns public `Summary` values,
  keeps credentials out of read models, and scopes reads and writes through a
  company already proven by `Bilimbi.Core.Company`.
- [x] Module/dependency boundaries — Company and Employee are reached through
  their public APIs; the package does not query their owned schemas.
- [x] Belimbing schema/data compatibility — the five owned tables, UUID
  notification key, fixed-width `user_pins.url_hash`, nullable Company/Employee
  foreign keys, and complete `company_external_accesses.user_id` optional group
  match the canonical migration set pinned by the task.
- [x] Tenant, authorization, and soft-delete behavior where relevant — users
  carry no `tenant_id`; a nil-company user is invisible, and cross-tenant
  Company access is rejected before the User query runs. User has no soft-delete
  contract in the pinned source.
- [x] Failure paths and operational observability — missing/foreign Company and
  Employee affiliations return bounded errors, duplicate email is a changeset
  error, and plaintext or malformed credentials are rejected before persistence.
- [x] Focused tests and documentation — User 12/12 and Compatibility 10/10 pass
  independently on the reviewed integrated state; package documentation records
  the S1 boundaries and deferred work.
- [x] No unrelated or unclaimed changes — PR #21's product files are confined to
  `apps/core/user/**`; its coordination changes are the task card and the
  implementer's sender-owned mailbox.

## Validation independently performed

- Compared the reviewed migration and schema contract with Belimbing commit
  `e70b4d33c0b10790e681f4c2b5095d85a53bc918`, specifically
  `app/Core/User/Database/Migrations/0200_01_20_000000` through `000005` and
  the end-state effects of `000007`.
- Rechecked the tenant-wide source read at
  `app/Core/User/Livewire/Users/Index.php:102-106`: it joins Company and filters
  by tenant. The current package intentionally exposes a narrower per-company
  read without crossing the Company schema boundary.
- Ran `mix test` in `apps/core/user`: **12 passed**.
- Ran `mix test` in `apps/core/compatibility`: **10 passed**.
- Rechecked BLB-S1-009's integrated fresh-schema evidence: all six baselines
  migrated, `mix bilimbi.schema.verify` passed, and root `mix precommit` passed
  with 114 tests. This closes the real-database verification caveat recorded in
  the BLB-S1-006 handoff.

## Follow-up tasks suggested

- Complete BLB-S1-010's tenant-wide Company/User list seam without exposing or
  querying the Company schema from Core User. Its acceptance decision must keep
  the already-recorded soft-deleted-company behavior explicit.
