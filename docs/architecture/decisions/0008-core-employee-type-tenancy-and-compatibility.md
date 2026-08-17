# ADR 0008: Core Employee Type Tenancy and Compatibility Migration

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** antigravity
**Scope:** Core Employee Type tenancy ownership, partial index constraints, migration disposition, and administration APIs
**Last Updated:** 2026-08-17

## Context

Belimbing commit `e70b4d33c0b10790e681f4c2b5095d85a53bc918` creates the `employee_types` table with the following schema:
- `id` (bigserial primary key)
- `code` (string, not null)
- `label` (string, not null)
- `is_system` (boolean, not null, default false)
- `company_id` (bigint, nullable)
- timestamps (`created_at`, `updated_at`)

It defines a global unique index `employee_types_code_unique` on `(code)` and secondary indexes on `(company_id)` and `(company_id, code)`.

In Belimbing's application code, `EmployeeType` model used `->global()` (`whereNull('company_id')`), meaning the UI only exposed global employee types and never populated `company_id`.

When Bilimbi established explicit tenancy (AGENTS.md §5: "Every Company write must receive or derive an explicit, validated tenant"), Core Employee partitioned employee types into:
1. **System types:** Platform-wide defaults (`is_system = true, company_id = NULL`) bootstrapped into the system.
2. **Company custom types:** Company-owned custom types (`is_system = false, company_id = company_id`).

However, the compatibility baseline migration reproduced the inherited global unique constraint `employee_types_code_unique` on `(code)`. In a multi-tenant system, this global constraint creates a critical multi-tenant collision: two independent companies cannot both define a custom employee type with the same code (e.g., `intern`, `contractor`, or `probation`).

Issue #149 researched this conflict and established that:
- Bilimbi's company-owned custom type model is the correct product and tenancy architecture.
- The schema's nullable `company_id` column was originally intended for company ownership.
- The inherited global unique index on `(code)` must be adapted via an explicit Bilimbi-only migration to partial unique indexes.
- Administration APIs (`update_employee_type/4` and `delete_employee_type/3`) are required to achieve full management parity and unblock UI task #97.

## Decision

### 1. Preserve Company-Owned Custom Types and System Type Protection

- System types have `is_system = true` and `company_id = NULL`. They are platform-wide, read-only for tenants, and cannot be updated, deleted, or shadowed by tenant custom types.
- Custom types in Bilimbi have `is_system = false` and non-null `company_id`. They belong strictly to their owning company and are isolated by `%Scope{}`.
- Legacy global custom types from Belimbing (`is_system = false, company_id = NULL`) retain global uniqueness under `employee_types_global_code_unique`.
- Codes are durable and immutable after creation.
- Custom type creation must continue to reject reserved system codes (`reject_reserved_system_type_code`).
- Database check constraint `employee_types_system_company_check` enforces `NOT is_system OR (company_id IS NULL)`, ensuring at the PostgreSQL level that system types cannot belong to a company.

### 2. Bilimbi-Only Compatibility Migration

To resolve the multi-tenant code uniqueness constraint without breaking compatible schema baselines or adoption verification:

1. The initial baseline migration `20260812112641_create_core_employee_compatibility_baseline.exs` remains classified as `:compatible_baseline`.
2. Migration `20260817173000_adapt_employee_types_tenancy_indexes.exs` was introduced with disposition `:bilimbi_only`:
   - Drops global unique index `employee_types_code_unique` on `(code)`.
   - Creates partial unique index `employee_types_global_code_unique` on `(code)` where `company_id IS NULL AND is_system = true`.
   - Creates composite partial unique index `employee_types_company_code_unique` on `(company_id, code)` where `company_id IS NOT NULL`.
3. Migration `20260817180000_broaden_global_index_and_add_system_company_check.exs` is introduced with disposition `:bilimbi_only`:
   - Broadens partial unique index `employee_types_global_code_unique` on `(code)` to `WHERE company_id IS NULL`, eliminating the uncovered uniqueness quadrant and safely covering all global rows (system and legacy Belimbing global custom types).
   - Adds database check constraint `employee_types_system_company_check CHECK (NOT is_system OR (company_id IS NULL))`.
4. In `apps/core/employee/bilimbi.module.exs`, `migration_dispositions` explicitly registers:
   ```elixir
   migration_dispositions: %{
     20_260_812_112_641 => :compatible_baseline,
     20_260_817_173_000 => :bilimbi_only,
     20_260_817_180_000 => :bilimbi_only
   }
   ```
5. `SchemaContract` registers the indexes and check under `optional_groups` (`name: "core/employee type tenancy adaptation"`), ensuring schema verification enforces all-or-nothing presence of the adapted indexes and check constraint.
6. **Down-Migration Reversibility:** Reversing `20260817180000` drops the check constraint and restores the narrower index predicate; reversing `20260817173000` via `down` restores the single global unique index on `(code)`. Note that executing `down` on `20260817173000` against a live multi-tenant database requires reconciling duplicate codes across companies if multiple companies have created custom types sharing a code.

### 3. Adoption Behavior for Existing Databases

When adopting an existing Belimbing database (`mix bilimbi.schema.adopt`):
- Schema verification checks against `SchemaContract` (which reflects the baseline schema or the complete adapted group).
- The baseline migration `20260812112641` is recorded as adopted in `bilimbi_schema_migrations`.
- `mix bilimbi.migrate` executes the pending `:bilimbi_only` migrations `20260817173000` and `20260817180000`, replacing the global index with the partial indexes and adding the system/company check constraint.
- Existing Belimbing custom rows where `company_id IS NULL` and `is_system = false` are fully preserved, retain code uniqueness under the broadened `employee_types_global_code_unique` (`WHERE company_id IS NULL`), and satisfy `employee_types_system_company_check`.

### 4. Public Administration APIs

Core Employee exposes the following public functions without leaking schemas or internal queries:

- `list_employee_types(scope, company_id)`: Returns all system types and the specified company's custom types, ordered by `[desc: is_system, asc: label, asc: code]`.
- `create_employee_type(scope, company_id, attributes)`: Creates a custom employee type for `company_id` after validating that the code is not reserved.
- `update_employee_type(scope, company_id, type_id, attributes)`: Updates a company's custom employee type. Only `:label` is mutable; `:code` and `:is_system` are immutable. Returns `{:error, :is_system}` if attempting to update a system type.
- `delete_employee_type(scope, company_id, type_id)`: Deletes a custom employee type after verifying under row lock that:
  1. The type belongs to `company_id` and `is_system = false` (returns `{:error, :is_system}` otherwise).
  2. No employee in `company_id` references the type's `code` (returns `{:error, :in_use}` otherwise).

## Consequences

- **Pros:**
  - Distinct companies can define custom employee types with identical codes without collision.
  - System types remain globally protected and immutable.
  - Invariant `is_system = (company_id IS NULL)` is guaranteed at database level.
  - Edit and delete parity is achieved for Employee Types, unblocking UI task #97.
  - Follows established Bilimbi migration disposition architecture (ADR 0002, ADR 0005).
- **Cons:**
  - Requires one additional Bilimbi-only migration in Core Employee.
