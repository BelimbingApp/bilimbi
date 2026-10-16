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

Cross-module writers follow the lock order on
`Bilimbi.Core.Company.lock_writable_company/2`. Within each module they lock
ascending IDs. A returned proof is useful only
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
   date field. An employee update or delete first locks and rechecks the writable
   company inside the transaction (`Company.lock_writable_company/2`), then locks
   the mapped person and affiliation before the employee row
   (`Person.lock_legacy_employee/2`), so a
   concurrent Contacts edit queues instead of deadlocking. A retired person or
   an unlinked affiliation is only read. An employee that has no mapping yet
   gets one from its complete stored facts on its next create or edit. Contacts owns retire and unlink: the sync leaves a retired
   person and an unlinked affiliation untouched, and the employee write still
   succeeds. Deleting an employee unlinks its mapped affiliation and sets its
   end date in the same transaction; the Core person stays.

Core Person's retirement or affiliation unlink preserves legacy records and
never terminates HR employment, clears user links or changes permission grants.
The mapping migration preserves null timestamps and advances the person sequence.
The Person structure migration refuses rollback while identity rows exist, so
rollback cannot erase contacts or their history; an empty installation can roll
back normally.

## Employment owner and HR handoff

People owns employment facts once it claims them, but Core has no descriptor
edge to People and must boot and behave the same without it. Three public
contracts carry the handoff; with People absent none of them changes a
result Core returned before.

- **Runtime owner seam.** The owner calls
  `register_employment_owner/1` from its application start and
  `unregister_employment_owner/1` on stop; the registration lives in
  `:persistent_term`, one owner at a time. While one is registered, every
  write of a legacy row (`create_employee/3`, `update_employee/4`,
  subordinate assignment and removal, `delete_employee/3` and
  platform-orchestrator provisioning) calls its
  `legacy_employee_written/2` inside the same transaction, after Core's
  company, person/affiliation and employee locks and after Core's own write.
  Core reads the registered owner inside that transaction, after those
  locks (an insert takes the company lock only when an owner is registered),
  so a write that finds none takes no extra lock. The callback receives the
  scope and one map of `employee_id`, `person_id` and `affiliation_id`
  (`nil` for both IDs when it has no mapping; for a delete, the mapping the
  deleted row had; owners ignore keys added later), so the owner needs no
  list-capability read. An owner refusal rolls the whole write back and reaches the caller. With no owner
  registered, nothing is called and no extra lock is taken. A Core write already
  in flight when an owner registers may not call it. The owner therefore runs
  its adoption pass over `hr_handoff_page/3` after registering, and a second
  pass after a grace period longer than any Core HR transaction (for example
  60 seconds) that compares `updated_at` and includes newly inserted IDs.
  One pass alone does not close the race, and Core keeps no reconcile state.
  `Bilimbi.Core.Employee.EmploymentOwner` owns the callback contract.
- **Batch, permission-neutral mapping.** `person_identities/2` resolves up
  to 1,000 employee IDs to their person, affiliation and company IDs with a
  query count that does not grow with the batch. It returns IDs only, so it asks the employee read
  (`admin.employee.list`), not the contact view `person_identity/2` needs.
  It sees the tenant's rows, archived companies included.
- **Tenant-wide handoff read.** `hr_handoff_page/3` pages every retained
  row of the tenant by ascending ID (archived companies, agents and the
  platform orchestrator included) with the HR facts, metadata, clocks and
  person mapping. It writes nothing. Register the owner before paging, so a
  write that starts after registration reaches the owner through its
  callback; a write in flight at registration needs the second, later pass
  described above.

The employee list and record page say who owns the employee number, type,
status and employment dates when an owner is registered, and the record
page links to the owner's page for that employee
(`employment_ownership/3`). The facts stay editable there and every edit
reaches the owner. Agent discovery is validated at boot and cannot follow a
runtime registration, so the `core.employee` guide says it in words that
hold whether People is installed or not.

### Deprecation

The `core.employee.*` agent operations and the Core Employee HR fields they
write (employee number, type, status, employment dates and metadata) are
deprecated as of Bilimbi 0.1.0, in favour of the owner's operations and
`core.person.*` for contacts and affiliations. They keep working, with or
without an owner. Removal comes only in a later, separately reviewed release,
once integrations have an announced migration path.

Foreign keys from People's employment table to `core_people` and
`core_person_affiliations` sit on People's own table, so People declares them
in its own schema contract; Core has nothing to add for them.
