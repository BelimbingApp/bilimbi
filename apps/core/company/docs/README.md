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
