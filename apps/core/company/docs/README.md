# Core Company

`apps/core/company/` is the complete physical boundary for the required
`core/company` deep module. Its public API is `Bilimbi.Core.Company`; schemas,
primary-company workflows, operator/customer provisioning commands,
compatibility migrations, and tests remain inside this directory.

The module depends on the public Base Database and Tenancy contracts. Callers
must not reach into `Bilimbi.Core.Company.Schema` or its internal workflow
modules.

Company publishes `addressable_identity/0` as the source of truth for its
durable Belimbing polymorphic identity. Modules that attach data to a Company
must use that API instead of duplicating the persisted string.

## Tenant-wide reads

| Function | Soft-deleted companies |
|---|---|
| `list_companies/1` | Excluded — matches `get_company/2` |
| `list_tenant_company_ids/1` | Included — Belimbing-compatible user listing seam |

Core User's tenant-wide list consumes `list_tenant_company_ids/1` so it never
queries `companies` directly (BLB-S1-010 option a).

## External access

`company_external_accesses` is owned here. `user_id` is an optional opaque
identity contributed by Core User; this module never queries `users`. The
caller (Core User / Web) must prove the user belongs in the tenant before
passing that identity. `relationship_id` must belong to the granting company.

| Function | Notes |
|---|---|
| `list_external_accesses/2` | Live rows for one granting company, oldest id first, capped |
| `list_external_accesses/3` | Same, filtered by a positive opaque `user_id` |
| `list_external_accesses_for_user/2` | Live rows for one user across live companies in the scope |
| `get_external_access/3` | Live row in the granting company |
| `create_external_access/3` | Requires a company-owned relationship |
| `update_external_access/4` | Dates, permissions, activity |
| `grant_external_access/3` | Sets `is_active` and `access_granted_at` |
| `revoke_external_access/3` | Sets `is_active` false |
| `delete_external_access/3` | Soft-delete; fetch-and-mutate locks the live row |

`ExternalAccessSummary.valid?/1,2` matches Belimbing `isValid()`: active, not
pending, and not expired.
