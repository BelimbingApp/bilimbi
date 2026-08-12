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
