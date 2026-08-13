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
transaction. `list_tenants/0` and `count_tenants/0` enumerate live tenants as
`Identity` values for administration and visibility; they omit soft-deleted
rows and do not leak the schema. Web must authorize those reads with
`admin.tenancy.tenant.list` rather than the operator marker.

## Scope

`Bilimbi.Base.Tenancy.Scope` is the validated tenant boundary for one unit of
work. `scope/1` resolves a tenant ID once and returns a scope only for a live
tenant, so a module holding a scope holds proof it need not re-check.

`scope_query/2` is the sanctioned way to begin a read of tenant-owned data on
behalf of a caller:

```elixir
{:ok, scope} = Tenancy.scope(tenant_id)

from address in Tenancy.scope_query(Schema, scope),
  where: is_nil(address.deleted_at)
```

It has exactly one clause, so a `nil`, a bare tenant ID, or a forgotten
argument raises instead of producing an unfiltered query. The first binding is
named `:scoped`, which correlated subqueries reference with
`parent_as(:scoped)`.

A module that owns a tenant-scoped invariant may still query its own tables
directly — `Bilimbi.Core.Company.PrimaryCompanyManager` locks rows and
deliberately looks across tenants to prove a company is unclaimed. That is a
different operation from serving a caller's read, and it stays explicit inside
the owning module.
