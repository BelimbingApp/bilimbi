# Core Address

`apps/core/address/` is the complete physical boundary for the required
`core/address` deep module. Its public API is `Bilimbi.Core.Address`; schemas,
polymorphic attachment compatibility, migrations, and tests remain inside this
directory.

The module depends on Base Database, Base Locale, Base Tenancy, Core Geonames, and the public
Core Company API. It owns the two Address-to-Geonames normalization foreign
keys and preserves Belimbing's persisted camel-cased columns and morph
identities behind a tenant-explicit, snake-cased Elixir interface. It supplies
the bounded `%Bilimbi.Base.Locale.Bootstrap{}` facts for the platform
operator's primary company address to support one-time installation-locale
inference.

## Administration web adapter

Core Address contributes capability-gated routes from `priv/web_routes.exs`.
The module-owned administration index uses the bounded tenant page API for
search, sorting, pagination, and safe deletion. The create form writes only
through the public Address facade and obtains country, Admin1, postcode, and
locality choices from Core Geonames' public reference-data APIs.

The module-owned detail page is read-first: an operator holding
`admin.address.update` changes each fact where they read it and the commit
saves by itself, so the page has no edit mode and no save button. The
interdependent location facts are the one grouped Apply, and the header
carries record history as a demoted icon action beside plain "← Back" links.
`Bilimbi.Core.Address.Web.ShowLive`'s moduledoc owns the per-fact rules, and
DESIGN.md's "Read-first detail pages" owns the pattern.

Changing country clears all dependent location fields. Exact postcode matches
may populate a valid Admin1 division and a single unambiguous locality; manual
Admin1 or locality values remain distinguishable from those suggestions. The
LiveView never queries an Address or Geonames schema directly.
