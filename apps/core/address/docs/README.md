# Core Address

`apps/core/address/` is the complete physical boundary for the required
`core/address` deep module. Its public API is `Bilimbi.Core.Address`; schemas,
polymorphic attachment compatibility, migrations, and tests remain inside this
directory.

The module depends on Base Database, Base Tenancy, and the public Core Company
API. It preserves Belimbing's persisted column and morph identities behind a
tenant-explicit Elixir interface.
