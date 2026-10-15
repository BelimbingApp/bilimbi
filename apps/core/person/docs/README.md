# Core Person

Core owns person identity and person–company affiliations. `Bilimbi.Core.Person`
is the public API; its persistence schemas are private. It requires no People
module. Creating a namecard contact records a name, an existing affiliated
company, and optionally title, email and phone. It creates no HR number,
employment type/status/dates, login account, principal grant or portal access.
An affiliation can describe employment at a vendor without claiming that our HR
team administers that employment.

A namecard's email and phone are work contact details: `create_contact/3` stores
them on the affiliation only, and the person keeps identity (name) alone. A person
with no company (a lead, created with `create/2`) keeps its email and phone on the
Person. The legacy-employee backfill follows the same rule (the employee's work
email and mobile live on the affiliation). Duplicate search covers both. Person
and affiliation reads are tenant-wide by design, gated by `admin.person.list` and
`admin.person.view`.

Search names/email/phone with `list/2` before creating. Matching data never
implicitly merges identities. Use `create_contact/3` to create the identity and
its affiliation atomically, or `create/2` then `link/4`. Reuse an existing
person by ID for each additional company. A person's contact details
and an affiliation's company-specific title/contact details can evolve separately.

Every caller supplies a sealed Tenancy Scope. UI and agent operations stand on
`admin.person.list`, `.view`, `.create` and `.update`. Affiliate targets use
`Company.authorize_company_target/3`; another company requires tenant-wide
company reach, and an archived company refuses affiliation writes. Affiliation
writes lock Company, then Person, then affiliation; retirement and edits lock
Person, so archive, retirement and unlink cannot race a later contact write. Personal
identity belongs to the tenant, not exclusively to one employer. All reads are
tenant-scoped, field restrictions apply to summaries and writes, and Repo writes
carry the performing scope into audit capture. Retired identity remains readable
but read-only and leaves active searches. Unlink keeps the affiliation and its
stable ID and sets its end date (today, unless an earlier end date is recorded);
linking again creates a new retained link. An affiliation carries optional
`started_on` and `ended_on` dates (the end on or after the start), shown and
editable on the contact page; a person can hold several, each with its own
dates. Existing affiliations were dated on migration: the legacy employee's
employment start and end where known, otherwise the creation and unlink dates.

The UI is `/contacts`, `/contacts/new` and `/contacts/:id`. Supported headless
operations are discoverable under `core.person.*`:

| Operation | Purpose |
| --- | --- |
| `list`, `get` | Duplicate search and identity/affiliation reads |
| `create`, `update`, `retire` | Identity lifecycle |
| `contact.create` | Namecard identity and affiliation in one transaction |
| `affiliation.list` | Retained affiliation history |
| `affiliation.link`, `affiliation.update`, `affiliation.unlink` | Reuse identity and maintain company contact facts and `started_on`/`ended_on` dates; unlink sets the end date |
| `relationship.list`, `relationship.get` | Roles a person holds toward a company, including unlinked history |
| `relationship.create`, `relationship.update` | Assign a role; change its dates |
| `relationship.end` | Normal transition: set `effective_to` (default today) and keep the row as dated history |
| `relationship.unlink` | Remove a mistaken entry (soft delete); the row is retained but leaves active lists |

Use discovered input schemas; tenant, actor and HR fields are not inputs.
Writes use the existing agent preview/review/approval/plan-code commit contract.
Preview is nonmutating; commit repeats validation and authorization. Effective
write policy is checked for both the signed-in company and affiliation target,
including updates and unlinks resolved from their stored affiliation ID.

Core Company owns the existing role catalogue and intercompany relationships;
see its README. Vendor/customer/prospect/partner are simultaneous relationship
roles, not mutually exclusive legal types. Neither a role nor an affiliation
grants access. Account and external-access administration remain explicit workflows.

# Person roles

A role links our side to either an organisation or a person, never both:
a company-to-company link lives in Core Company (`company_relationships`), and
a company-to-person link lives here in `core_person_relationships`
(`Person.relationships/3`, `create_relationship/4`, `update_relationship/4`,
`unlink_relationship/3`). Both use the one Company role catalogue, so there is
no second taxonomy. Core Company cannot depend on Person, which is why the
person-targeted link is owned here rather than as a nullable column there. For
source company A and person P with role customer, **P buys from A**; the
catalogue's inverse label describes A from P's side. A person can be a lead
with only a prospect role and no affiliation, hold several concurrent roles
toward the same company, and become a customer by ending the prospect link
(`end_relationship/4`, `effective_to` defaulting to today) and creating the
customer link; both rows are retained with their dates. Unlinking is only for
removing a mistaken entry and records `deleted_at`, not an end date. Live links for one company, person and role may not overlap in time
(inclusive dates, an absent date being open); create, update and the previews
refuse an overlap, enforced in the write transaction under a per-pair advisory
lock beside the open-ended unique index, and an exact repeat of a create returns
the existing link; retired roles cannot be newly assigned and existing links survive
retirement. A role writes under `admin.person.update`, locks Company, then
Person, then the role, refuses an archived company or retired person, and honours
the company's agent write switch. Roles confer no access, employee number or
login. `/contacts/:id` shows the person's roles with start and end dates and, for an
unlinked row, when it was unlinked. It offers add, edit dates, End role (date
defaults to today and is editable) and Unlink.

# Legacy identity mapping

The Employee-owned migration copies each existing employee's name/contact
facts to a Core Person and its designation to an affiliation. It leaves every
legacy HR row and reference unchanged. Imported person IDs match employee IDs;
`legacy_employee_id` on the affiliation is the explicit mapping, and callers
must use it rather than assume that all future IDs match. The person sequence
advances beyond imported IDs. Null historical clocks remain null. No name/email
merge is attempted, including employees who share a user identity: deduplication
needs reviewed evidence.

Use `legacy_affiliation/2` or `Employee.person_identity/2` to resolve an existing
ID under the tenant boundary. Employees created or edited later through
`Employee.create_employee/3` and `update_employee/4` are mapped in the same
transaction (`sync_legacy_employee/4`), so they appear in `list/2` duplicate
checks and resolve through `person_identity/2`. Mappings retain system agents as well as humans;
SYS-001's durable orchestrator identity and its existing protection are untouched.
See Core Employee's README for the People handoff and deprecation contract.
The structure migration refuses rollback while identity rows exist, because
dropping it would destroy contacts and affiliation history. An empty fresh
installation may roll back normally. Recover from a reviewed
backup rather than silently erasing these records.
