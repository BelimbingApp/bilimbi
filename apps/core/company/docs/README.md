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

The module-owned detail and list page headers follow DESIGN.md's "Demoted
secondary actions" pattern; `Bilimbi.Core.Company.Web.ShowLive`'s moduledoc owns
the detail header contract.

## Lifecycle

A company's `status` is a lifecycle, not an attribute. `update_company/3`
refuses a `status` key with a changeset error; a status changes only through
one of these operations, each a named verb on `Bilimbi.Core.Company` whose
body is `Bilimbi.Core.Company.Lifecycle`:

| Operation | From | To | Audit event |
|---|---|---|---|
| `activate_company/3` | `pending` | `active` | `company.activated` |
| `reactivate_company/3` | `suspended` | `active` | `company.reactivated` |
| `suspend_company/3` | `active` | `suspended` | `company.suspended` |
| `archive_company/3` | `pending`, `active`, `suspended` | `archived` | `company.archived` |

`pending` is an initial state only: `create_company/3` accepts `active` (the
default) or `pending` and nothing else, and `activate_company/3` is the one
way out. `archived` is final: no operation starts from it, matching the rule
in `apps/core/AGENTS.md` that archiving is not undone. Any other pairing is
`{:error, {:invalid_transition, current_status}}`, a refusal the caller can
name rather than a changeset error on a field.

Every operation:

- takes the sealed `%Bilimbi.Base.Tenancy.Scope{}` of the person performing
  it and requires `admin.company.update` on it now, through
  `authorize_company_target/3`: the capability where the person signed in is
  enough for that company, and any other company of the tenant additionally
  requires `admin.company.tenant-wide.manage`. Holding the update capability
  at one company never reaches another. The lifecycle shares the update
  capability rather than owning one of its own; a system scope names nobody
  and is `{:error, :forbidden}` because a business event records who
  performed it. The company page shows the controls only where this holds
  and says why when it does not;
- accepts `reason:` as an option: trimmed, blank recorded as none, at most
  `lifecycle_reason_max_length/0` characters, counted as characters and not
  bytes (`{:error, :reason_too_long}`); a reason that is not text is
  `{:error, :invalid_reason}`;
- locks the live row, judges the transition against the status it will
  overwrite, writes it, and records one retained `base_audit_actions` row
  with the event above in the same transaction. The payload is the semantic
  shape the impersonation and system-principal records use: `summary`
  ("Archived company “Name”"), `subject` (`company`, its id and name) and
  `context` with `from_status`, `to_status` and `reason`. If the action
  cannot be recorded the status write is rolled back
  (`{:error, :audit_unavailable}`). The captured mutation on `companies`
  still records the field values; the action records the intent;
- for `archive_company/3` and `suspend_company/3`, which take a company out
  of service, refuses the tenant's primary company
  (`{:error, :primary_company}`, judged against the assignment under the
  row lock) and the company the performing account signed in under
  (`{:error, :own_company}`, the scope actor's `company_id`), after the
  transition itself has been judged. The tenant and the operator stand on
  those companies; activate and reactivate are never refused for this;
- returns `{:error, :not_found}` for a missing, soft-deleted or cross-tenant
  id, as `get_company/2` does.

`lifecycle_operations/1` answers which operations a status offers, in the
fixed order activate, reactivate, suspend, archive; a page renders exactly
those controls. The company page offers them beside the status badge and
commits each through one dialog that names the consequence and takes the
reason (`Bilimbi.Core.Company.Web.ShowLive`).

### An archived company is read-only

An archived company is read-only for good, and so is every record it owns.
Every write to the company or into it begins with one guard,
`Bilimbi.Core.Company.WritableCompany`, reached through
`require_writable_company/2` (or `lock_writable_company/2` for a sibling
workflow that takes the company row lock first) and refused with
`{:error, :company_archived}`. Base modules reach the same answer through
`Bilimbi.Base.Authz.company_writable/2`, which the Authz company directory
answers from that guard. Reads never ask it: an archived company and its
records stay listed, viewable and auditable.

| Write | Guarded in |
|---|---|
| `update_company/3`; moving the tenant's primary company onto it | `company.ex`, `primary_company_manager.ex` |
| Departments: create, status, head, delete | `departments.ex` |
| Relationships: create, update, delete, on either side; an archived company is not offered as a related company | `relationships.ex` (`:related_company_archived` for the other side) |
| External accesses: create, update, grant, revoke, delete | `external_accesses.ex` |
| Address attachments to the company or its employees; an address such a company or employee links to | Core Address |
| Employees and employee types: create, update, delete, subordinates, affiliation lock | Core Employee |
| User accounts: create, update, delete, employee link, moving an account into it | Core User |
| Roles, role capabilities, role assignments, direct and system-principal grants | Base Authz |
| Company-scoped settings and shared workspace layouts | Base Settings (through the host's `SettingsCompanyScope.writable/2`), Base Tiling |

The lifecycle table above already ends at `archived`. Pages withhold their
edit, create and delete controls and show one "archived and read-only"
notice, but the refusal lives in the domain, so a stale or forged commit is
refused too.

An archived company's accounts cannot sign in, be impersonated, or keep a
session. `fetch_tenant_id_for_company/1`, the Web login edge's one company
read, answers `{:error, :company_archived}`, so the login form says so and
every request or LiveView event of a session opened before is refused. Each
committed lifecycle operation is published to `subscribe_lifecycle/0`; on
`archive` the host (`BilimbiWeb.CompanySessionTermination`) asks Core User
to end the company's sessions (`User.terminate_company_sessions/2`) so open
tabs close at once. Nothing stores the refusal: it is read from the status
on every request, so sign-in follows the status if it ever changes back.

Soft deletion (`deleted_at`) is a separate fact from the `archived` status,
as it is in Belimbing, where `archive()` sets the status and `delete()`
retires the row. A soft-deleted company is not found at all. There is no
`delete_company` in this API today.

## Tenant-wide reads

| Function | Soft-deleted companies |
|---|---|
| `list_companies/1` | Excluded — matches `get_company/2` |
| `dashboard_summary/2` | Excluded — counts all live companies and returns the preferred company, or the first live company by ID |
| `live_company_ids_query/1` | Excluded — id query of the same set as `list_companies/1` |
| `list_live_company_ids/1` | Excluded — id-only form of `list_companies/1` |
| `live_company?/2` | Excluded — one id, existence only |
| `identity/2` | Excluded — one id; `%{id, code, display_name}` from one tenant-scoped query |
| `require_live_company/2` | Excluded — `{:ok, id}` or `{:error, :not_found}` from the same existence query; builds no summary, so an existence-only caller uses it instead of `get_company/2` |
| `list_tenant_company_ids/1` | Included — Belimbing-compatible user listing seam |

A caller picks the cheapest read that answers its question. `get_company/2`
returns the summary: a caller that shows the company to a reader uses it. A
caller that needs only existence or the id uses `require_live_company/2`,
and one that needs only the id, code and name uses `identity/2`.
`authorize_company_target/3` answers the authorized company's summary, so a
page that authorizes a target can name it. Core Employee, Core User and Core Address check a
company before a write through `require_writable_company/2`; `BilimbiWeb.UserAuth`, the employee page
and the Departments and Relationships pages read the name through
`identity/2`; `Company.Web.ShowLive` reads the summary.

Core User's tenant-wide list consumes `list_tenant_company_ids/1` so it never
queries `companies` directly (BLB-S1-010 option a).

## Field access

An operator may restrict any non-protected field of the `companies` catalog
table to roles (Administration › Authorization › Field Access). Every summary
this module returns is built through `Summary.for_scope/2`, so a reader who
holds none of those roles gets a `Bilimbi.Base.Authz.Restricted` marker in
that field; `create_company/3` and `update_company/3` refuse any attempt to
set it with an error on the field, whatever the value; the administration
search skips the column (`searchable_columns/1`); the companies grid leaves
the column out; and the record history and `/audit/mutations` withhold its
values through the table's `record_types` (`auditable_types/0`). `code` and
`status` are protected, and the key `id` and the label `name` are protected
implicitly. `restricted_field_markers/1` returns the restricted summary keys with their
`Restricted` markers for the create and setup forms, which show them as
`<.restricted_field>` rows naming the roles that see each. The
seam itself is Base Authz's (`apps/base/authz/docs/README.md`
"Field-level authorization").

## Authorized company reach

`list_selectable_companies/2` and `authorize_company_target/3` combine an
actor's operation capability with its permitted company reach. Pass the sealed
`%Bilimbi.Base.Tenancy.Scope{}`: that clause derives the actor with
`Bilimbi.Base.Authz.scope_actor/1`. The `%Bilimbi.Base.Authz.Actor{}` clauses
remain for a caller that already holds one, and both forms return the same
result for the same sealed user. A system scope names nobody and is
unauthorized. Do not build an actor with `Authz.actor/5` to reach these
functions. An actor may always target its own company for an allowed
operation. Targeting a sibling company additionally requires
`admin.company.tenant-wide.manage`, which the configured `tenant_owner` role
receives. The reach capability never authorizes an operation by itself.

Both APIs start from the actor's validated tenant scope, so a company in a
different tenant remains unavailable even to `tenant_owner` and `core_admin`.
Callers use these APIs for selector options and repeat the target check on
submit; they do not inspect role codes or infer authority from the platform-
operator tenant marker.

## Transactional live-company proof

`lock_live_company/2` is the Company collaboration seam for a sibling workflow
that already holds an explicit shared `Bilimbi.Base.Repo` transaction. It locks
one live Company row through the supplied `%Bilimbi.Base.Tenancy.Scope{}` and
returns `LiveCompanyProof`, a schema-free value containing only its id. Missing,
cross-tenant, deleted, and malformed ids all return `{:error, :not_found}`;
calling outside an explicit transaction returns `{:error, :transaction_required}`.

The proof remains valid only until that transaction commits or rolls back. A
cross-module workflow acquires locks in this order: Company, then Employee,
then User; within each record kind, ids ascend. It must not take an Employee or
User lock before calling `lock_live_company/2`.

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
