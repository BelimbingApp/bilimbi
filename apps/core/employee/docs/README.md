# Core Employee

`core/employee` owns employment relationships inside companies. Its physical
boundary is this directory and its public namespace is
`Bilimbi.Core.Employee`.

Employee records are deliberately separate from authentication users: an
employee may exist without system access, while a future Core User module owns
the optional account link. The first slice covers tenant-scoped employee CRUD,
department and supervisor validation, employee-type reference data, and the
compatible Employee schema.

The platform orchestrator is resolved by the explicit platform-operator
company plus the durable employee number `SYS-001`; numeric employee ID `1`
has no runtime meaning. `ensure_platform_orchestrator/0` provisions that record
idempotently and refuses a conflicting non-agent record. AI activation and
execution, User linkage, authorization, and web screens remain later slices.

`list_administration_page/3` is the bounded Employee-owned read model for an
administration index. It requires a tenancy scope and one live company proven
through the public Core Company facade before it queries employees. It accepts
only validated keyword options for page, page size (default 15, maximum 100),
literal case-insensitive search, human/agent filtering, and the Employee-owned
name/type/status sorts. Its entries expose only safe summary facts and it
returns deterministic ID-descending ties plus complete pagination metadata.

The pinned Belimbing screen can also sort by company name because it is a
tenant-wide query. Bilimbi's current public contract is deliberately one
explicit company, so company ordering would be constant and is omitted rather
than adding a private Company query or implying an unimplemented cross-company
administration boundary.
