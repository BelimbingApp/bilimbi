# Core Address

`apps/core/address/` is the complete physical boundary for the required
`core/address` deep module. Its public API is `Bilimbi.Core.Address`; schemas,
polymorphic attachment compatibility, migrations, and tests remain inside this
directory.

The module depends on Base Database, Base Tenancy, Core Geonames, and the public
Core Company API. It owns the two Address-to-Geonames normalization foreign
keys and preserves Belimbing's persisted camel-cased columns and morph
identities behind a tenant-explicit, snake-cased Elixir interface.

## Administration web adapter

Core Address contributes capability-gated routes from `priv/web_routes.exs`.
The module-owned administration index uses the bounded tenant page API for
search, sorting, pagination, and safe deletion. The create form writes only
through the public Address facade and obtains country, Admin1, postcode, and
locality choices from Core Geonames' public reference-data APIs.

Changing country clears all dependent location fields. Exact postcode matches
may populate a valid Admin1 division and a single unambiguous locality; manual
Admin1 or locality values remain distinguishable from those suggestions. The
LiveView never queries an Address or Geonames schema directly.
