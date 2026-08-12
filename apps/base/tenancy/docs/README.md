# Base Tenancy

`apps/base/tenancy/` is the complete physical boundary for the required
`base/tenancy` deep module. Its public API is `Bilimbi.Base.Tenancy`; schemas,
invariant errors, compatibility contracts, migrations, and tests remain inside
this directory.

The module depends only on `base/database`. It owns the compatible `tenants`
schema and explicit platform-operator identity. Numeric database IDs have no
runtime role meaning.

Callers receive `Bilimbi.Base.Tenancy.Identity`, never the private Ecto schema.
`fetch_tenant/1` and `lock_tenant/1` are the public tenant reads for
cross-module workflows; the latter holds the tenant row lock in the caller's
transaction.
