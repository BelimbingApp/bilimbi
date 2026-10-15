# Core Employee

`core/employee` owns employment relationships inside companies. Its physical
boundary is this directory and its public namespace is
`Bilimbi.Core.Employee`.

Employee records are deliberately separate from authentication users: an
employee may exist without system access, while Core User owns
the optional account link. The first slice covers tenant-scoped employee CRUD,
department and supervisor validation, employee-type reference data, and the
compatible Employee schema.

The platform orchestrator is resolved by the explicit platform-operator
company plus the durable employee number `SYS-001`; numeric employee ID `1`
has no runtime meaning. `ensure_platform_orchestrator/0` provisions that record
idempotently and refuses a conflicting non-agent record. AI activation and
execution, and User linkage, remain later slices.

`list_administration_page/3` is the bounded Employee-owned read model for an
administration index. It requires a tenancy scope and one live company proven
through the public Core Company facade before it queries employees. It accepts
only validated keyword options for page, page size (default 25, maximum 300),
literal case-insensitive search, human/agent filtering, and the Employee-owned
name/type/status sorts. Its entries expose only safe summary facts and it
returns deterministic ID-descending ties plus complete pagination metadata.

The pinned Belimbing screen can also sort by company name because it is a
tenant-wide query. Bilimbi's current public contract is deliberately one
explicit company, so company ordering would be constant and is omitted rather
than adding a private Company query or implying an unimplemented cross-company
administration boundary.

## Transactional affiliation proof

`lock_affiliation/3` is the public collaboration seam for a sibling workflow
that must prove one employee belongs to a live company before it writes its own
state. It accepts a tenancy scope plus positive company and employee IDs and
must be called inside the existing shared Repo transaction. Core Company first
locks and proves the live scoped company; Core Employee then locks the matching
employee by ID and the proved company ID and re-proves that affiliation after
any wait. The returned `%Bilimbi.Core.Employee.AffiliationProof{}` contains
only the stable employee and company IDs, never an Employee schema or query.

Employee rows do not have a `tenant_id`. Tenant ownership is therefore proven
by Core Company's public `lock_writable_company/2` contract rather than by copying
Company's private query or inventing a second tenant predicate. Employees are
hard-deleted in the compatible schema; the lock contract does not invent a
soft-delete or employment-status definition of "live". Missing, cross-tenant,
and company-mismatched identities deliberately collapse to `:not_found`; an
archived company is `:company_archived`. Only
the protected `SYS-001` plus `agent` platform-orchestrator pair fails closed
through this generic affiliation seam with `:invariant_violation`; a non-agent
legacy `SYS-001` row remains an ordinary affiliation under Employee's existing
invariant.

Cross-module writers use one strict lock order: **Company → Employee → User**.
Within each module they lock ascending IDs. A returned proof is useful only
inside the transaction that created it and must not be cached or treated as a
capability after commit or rollback.

## Web adapter

Web adapters live under `lib/employee/web/` as `Bilimbi.Core.Employee.Web.*`
and are discovered from `priv/web_routes.exs`. Screens are company-scoped
through the signed-in `company_id`: there is no tenant-wide employee list.
This is an initial module-owned adapter slice, not the complete pinned
Belimbing workflow. The employee and employee-type indexes keep their existing
URL keys through the shared filter toolbar. Deleting the platform orchestrator
is refused as `:invariant_violation`, and the show screen reports that honestly.

**The detail page is read-first.** `/employees/:id` shows the employee as
facts. An operator holding `admin.employee.update` edits the seven text facts
in place through `<.inline_edit>` (the nullable columns pass `allow_empty`)
and changes the department, supervisor, employee type and status through
choices that read as a name or badge and become a select on click; every
commit saves by itself and reports on its own fact through
`Bilimbi.Base.UI.CommitStatus`, so there is no "Edit employee" button and a
fact never reports through a flash. The company, employment start and end,
linked account, subordinates and addresses stay read-only or keep their own
workflows. `update_employee/4` accepts `nil` for a nullable text column, which
is how an in-place clear lands; the platform orchestrator's identity is
refused by the domain, and by Core User's `update_employee_type/4` as
`:invariant_violation`, and the page reports both on the fact.
`Bilimbi.Core.Employee.Web.ShowLive`'s moduledoc owns the per-fact rules and
DESIGN.md's "Read-first detail pages" owns the pattern. There is no
`/employees/:id/edit` route: the list's Edit action opens the record page,
and `FormLive` is reached only through `/employees/new` (its edit branch is
unrouted code until it is pruned).

**An employee type's record page is read-first too.** Belimbing gives a type
no detail page — its edit form is the record's page — and the rule reaches a
record whether or not its page is called a detail page. `/employee-types/:id`
(`Bilimbi.Core.Employee.Web.TypeShowLive`, under `admin.employee-type.list`)
shows the code, label and kind as facts; an operator holding
`admin.employee-type.update` edits the label in place through
`<.inline_edit>` and the outcome reports on the fact through
`Bilimbi.Base.UI.CommitStatus`. The code is permanent and a system type reads
as text for everyone. `/employee-types/new` (`TypeFormLive`) is create-only,
and the list's Edit action opens the record page.

## Employee Types administration

`list_employee_types/2`, `create_employee_type/3`, `update_employee_type/4`, and
`delete_employee_type/3` provide the public administration contract for employee
types. System types (`is_system = true, company_id = nil`) are immutable,
platform-wide, and cannot be modified or deleted. Custom employee types
(`is_system = false, company_id = company_id`) belong to one explicit company.
`update_employee_type/4` permits label updates only; codes are immutable.
`delete_employee_type/3` checks the `admin.employee-type.delete` capability
(anonymous system actors bypass the check) and then verifies under row lock
that the custom type is not referenced by any employee in the company
(`:in_use`).


## Agent writes

`core.employee.create` records a person at their own employer, including an
external company; it never creates a login. `employer_company_id` is a business
target authorized through `Company.authorize_company_target/3`, like the create
form's selector, and never substitutes the scope's person or signed-in company.
`core.employee.list` accepts the same optional target for duplicate searches;
omitting it searches the signed-in company.

`preview_create_employee/3` shares create's changeset, reserved-identity and
reference checks, plus a non-reserving uniqueness check. It writes nothing.
Commit calls `create_employee/3`, so the company must still be writable and its
references valid. The operation checks the signed-in and target companies'
agent-write switches, and the dispatcher asks `admin.employee.create` afresh.

An external employment report links to `/employees/:id?employer_company_id=...`.
The record page authorizes that employer through the same Company target API;
every page write rechecks the target permission, including tenant-wide reach.

## Deprecated HR compatibility and People handoff (issue 947)

Use `Bilimbi.Core.Person` and `core.person.*` for identity, contacts and general
person–company affiliations. `/contacts/new` and `core.person.contact.create`
accept a namecard without an employee number. `core.employee.create` and
`core.employee.list` are deprecated HR compatibility operations, explicitly
labelled that way in discovery and guides. Their input/output contracts remain
available for integrations and the mounted People workforce until its separate
migration. Never invent an employee number or use their legacy full_time/active
defaults to import a contact. The existing HR UI is compatibility administration;
it is not the contact creation workflow.

This Bilimbi change does not move or delete employment numbers, types, statuses,
dates, department/supervisor fields, job descriptions or metadata. With People
absent they remain readable through the existing Employee API and administration
pages. It changes no existing employee ID, company FK, user.employee_id,
department-head/supervisor FK, polymorphic Employee identity, principal grant or
system-agent reference. It also creates a Core Person/affiliation mapping for
each pre-existing row. `Employee.person_identity/2` and the discovered
`core.employee.person_identity` operation resolve that mapping (contact view
permission is required as well as the operation's employee read capability).
Mappings are tenant-scoped and their legacy IDs remain durable. No automatic
identity merge follows equal names or emails.

People's follow-up contract:

1. People owns employment numbers, employment type/status/dates and other HR
   facts. Its employment record references the returned Core Person ID and
   affiliation ID, with the employer from that affiliation; it does not copy
   mutable identity/contact facts into a second identity model.
2. Migrate every retained legacy row, including agent rows and HR metadata, with
   an explicit legacy-employee-to-People-employment mapping. Preserve legacy
   identifiers wherever integrations/FKs require them. Retain old user and
   principal references until their consumers deliberately adopt the mapping.
   Keep platform-orchestrator provisioning and system-agent resolution in Core,
   independent of People installation; publish a neutral Core identity mapping
   before retiring the protected SYS-001/agent compatibility lookup. A display
   name or coincident numeric ID must never become its runtime identity.
3. Claim existing data through a separately reviewed migration and schema
   ownership transition. Do not drop legacy columns or records when People is
   absent. Unmounting People must preserve its employment data and provenance.
4. After People reads identity through Core Person and ports its write workflows,
   redirect/deprecate the HR operations in a versioned compatibility release.
   Keep the old operations until integrations have an announced migration path.
5. Core Employee keeps the Core mapping in step while the HR rows stay here:
   `create_employee/3` and `update_employee/4` (and so `core.employee.create`
   and the Employee pages; there is no headless update operation) write the
   employee and its Core person and affiliation in one transaction. A new employee gets a person
   and an affiliation with its employer company, `legacy_employee_id` being the
   mapping; an edit carries only the facts that changed (name to the person;
   designation, work email, mobile number and employment start/end to the
   affiliation's title, email, phone and dates). Work email and phone live on the
   affiliation only. No HR field is copied, so People reads employment from the
   employee row and identity and contact from Core. A later Contacts edit is
   overwritten only by a later change to the same Employee fact. The synced
   dates pass through the affiliation's own validation: an employment date that
   would invert the affiliation's start/end range is refused on that employment
   date field. Deleting an employee unlinks its mapped affiliation and sets its
   end date in the same transaction; the Core person stays.

Core Person's retirement or affiliation unlink preserves legacy records and
never terminates HR employment, clears user links or changes permission grants.
The mapping migration preserves null timestamps and advances the person sequence.
The Person structure migration refuses rollback while identity rows exist, so
rollback cannot erase contacts or their history; an empty installation can roll
back normally. The mounted People repository is unchanged in this Bilimbi PR;
its existing workforce compile/test contract continues to use the retained HR API.
