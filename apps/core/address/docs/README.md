# Core Address

`apps/core/address/` is the complete physical boundary for the required
`core/address` deep module. Its public API is `Bilimbi.Core.Address`; schemas,
polymorphic attachment compatibility, migrations, and tests remain inside this
directory.

The module depends on Base Database, Base Tenancy, Core Geonames, and the public
Core Company API. It owns the two Address-to-Geonames normalization foreign
keys and preserves Belimbing's persisted camel-cased columns and morph
identities behind a tenant-explicit, snake-cased Elixir interface.
