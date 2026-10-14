# Core Person

Core owns person identity and person–company affiliations. `Bilimbi.Core.Person`
is the public API; its persistence schemas are private. It requires no People
module. Creating a namecard contact records a name, an existing affiliated
company, and optionally title, email and phone. It creates no HR number,
employment type/status/dates, login account, principal grant or portal access.
An affiliation can describe employment at a vendor without claiming that our HR
team administers that employment.

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
stable ID; linking again creates a new retained link.

The UI is `/contacts`, `/contacts/new` and `/contacts/:id`. Supported headless
operations are discoverable under `core.person.*`:

| Operation | Purpose |
| --- | --- |
| `list`, `get` | Duplicate search and identity/affiliation reads |
| `create`, `update`, `retire` | Identity lifecycle |
| `contact.create` | Namecard identity and affiliation in one transaction |
| `affiliation.list` | Retained affiliation history |
| `affiliation.link`, `affiliation.update`, `affiliation.unlink` | Reuse identity and maintain company contact facts |

Use discovered input schemas; tenant, actor and HR fields are not inputs.
Writes use the existing agent preview/review/approval/plan-code commit contract.
Preview is nonmutating; commit repeats validation and authorization. Effective
write policy is checked for both the signed-in company and affiliation target,
including updates and unlinks resolved from their stored affiliation ID.

Core Company owns the existing role catalogue and intercompany relationships;
see its README. Vendor/customer/partner are simultaneous relationship roles,
not mutually exclusive legal types. Neither a role nor an affiliation grants
access. Account and external-access administration remain explicit workflows.

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
ID under the tenant boundary. Mappings retain system agents as well as humans;
SYS-001's durable orchestrator identity and its existing protection are untouched.
See Core Employee's README for the People handoff and deprecation contract.
The structure migration refuses rollback while identity rows exist, because
dropping it would destroy contacts and affiliation history. An empty fresh
installation may roll back normally. Recover from a reviewed
backup rather than silently erasing these records.
