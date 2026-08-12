# BLB-S1-003 Review — codex/gpt-5

**Reviewer:** codex/gpt-5
**Role:** Independent architecture and compatibility reviewer
**Reviewed Commit/Diff:** Worktree changes above baseline `54b50b0`, limited to `apps/core/employee/**`
**Task Card:** [BLB-S1-003](../tasks/BLB-S1-003.md)
**Date:** 2026-08-12

## Verdict

`changes required`

## Findings

### Critical

None.

### Major

1. `apps/core/employee/lib/employee.ex:27-37` declares `(platform-operator primary company, "SYS-001")` as the system-agent identity, but the ordinary public create/update API does not reserve or protect that identity. `update_employee/4` can change the orchestrator's `employee_number` or `employee_type`; any caller can pre-create an `agent` numbered `SYS-001`, which `validate_platform_orchestrator/1` then silently adopts; and transferring the platform operator's primary company changes the lookup anchor, allowing a second orchestrator while future AI records remain keyed to the old employee ID. This is not yet a durable replacement for Belimbing's protected `LARA_ID`. Establish a persisted, immutable logical system-agent identity or an explicit transfer/rehome invariant, reject collisions rather than adopting arbitrary agent rows, protect identity-bearing fields through the public API, and test mutation, collision, deletion policy, and primary-company transfer.

2. `apps/core/employee/lib/employee.ex:102-121` bootstraps system types with `on_conflict: {:replace, [:label, :is_system, :company_id, :updated_at]}`. If an adopted or partially initialized database contains a tenant custom row using a reserved code such as `agent` or `full_time`, bootstrap silently converts it into a company-less system row. That changes ownership instead of reporting drift and conflicts with the handoff's protected system-type policy. Treat reserved-code conflicts as explicit invariants (or verify exact canonical rows before idempotent refresh) and add an adopted/conflicting-row test.

### Minor

1. `apps/core/employee/lib/employee.ex:28-37` omits `employment_start` when provisioning the platform orchestrator, while canonical Belimbing sets it on creation in `ManagesSystemAgents::provisionLara()`. The column is nullable, so this is not structural drift, but it is a business-data divergence in the very bootstrap behavior being ported. Either preserve the canonical creation-date meaning or document the intentional difference and test it.

## Acceptance-criteria check

- [ ] Public contract
- [x] Module/dependency boundaries
- [x] Belimbing schema/data compatibility
- [x] Tenant, authorization, and soft-delete behavior where relevant
- [ ] Failure paths and operational observability
- [ ] Focused tests and documentation
- [x] No unrelated or unclaimed changes

## Validation independently performed

- Read canonical Employee migrations, models, system-agent concern/exceptions, employee-type seeder, Company department migrations/models, and Employee tenant-boundary tests in Belimbing commit `e70b4d33c0b10790e681f4c2b5095d85a53bc918`.
- Compared all Employee columns, defaults, indexes, FK names/actions, JSON/timestamp types, and the depending-module `company_departments.head_id` FK against the Bilimbi migration and schema contract. No structural mismatch was found in the module-owned migration.
- Confirmed the descriptor keeps Employee required in Core and declares only Base Database and Core Company dependencies.
- Ran `mix test` from `apps/core/employee`: 7 passed.
- Ran `mix format --check-formatted` from `apps/core/employee`: passed.

## Follow-up tasks suggested

- Shared integration must register Employee's migration/schema contract, replay a fresh schema, and make `company_departments_head_id_foreign` required when Employee is installed; the task handoff already identifies this gate.
- Route Employee type bootstrap through the planned shared reference/bootstrap ledger rather than leaving it as an unrecorded one-off task.
