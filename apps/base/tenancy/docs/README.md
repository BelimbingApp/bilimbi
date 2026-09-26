# Base Tenancy

`apps/base/tenancy/` is the complete physical boundary for the required
`base/tenancy` deep module. Its public API is `Bilimbi.Base.Tenancy`; schemas,
invariant errors, compatibility contracts, migrations, and tests remain inside
this directory.

The module depends on `base/database`, `base/module_registry`, and `base/ui`
(for its admin adapter). It owns the compatible `tenants`
schema and explicit platform-operator identity. Numeric database IDs have no
runtime role meaning.

Callers receive `Bilimbi.Base.Tenancy.Identity`, never the private Ecto schema.
`fetch_tenant/1` and `lock_tenant/1` are the public tenant reads for
cross-module workflows; the latter holds the tenant row lock in the caller's
transaction. `list_tenants/0` and `count_tenants/0` enumerate live tenants as
`Identity` values for administration and visibility; they omit soft-deleted
rows and do not leak the schema. Web must authorize those reads with
`admin.tenancy.tenant.list` rather than the operator marker. The module-owned
admin adapter is `Bilimbi.Base.Tenancy.Web.TenantsLive` at `/tenancy/tenants`.

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

## The actor on a scope

Every scope carries a `Bilimbi.Base.Tenancy.Actor`, read with `Scope.actor/1`:

- `:system` for a scope from `scope/1` or `Scope.for_tenant/1` — scheduled
  work, seeds, mix tasks. It names no user and carries no authority.
- `:user` (with `company_id`, and `impersonator_id` under impersonation) only
  when Bilimbi's authentication edge attached it: `BilimbiWeb.UserAuth` for
  requests and LiveViews, and Base Queue for a job enqueued with
  `Queue.enqueue_for/3`.

A domain operation that records who performed it takes that person from
`Scope.actor/1`, never from its caller, and refuses a system actor. Whether the
person may do it is `Bilimbi.Base.Authz.can(scope, capability)`.

The edge seam is `Bilimbi.Base.Tenancy.Authentication`. It is not a domain
API, and the seal is what enforces that: the actor is sealed to its tenant
with an HMAC keyed by `config :bilimbi_base_tenancy, :actor_secret`
(production derives it from `SECRET_KEY_BASE`), so a struct literal, a struct
update, or an actor moved to another tenant's scope makes `Scope.actor/1`
raise `ForgedActorError`. The same secret signs the token a delegated job
carries; rotating it cancels such jobs still queued.

Before a delegated job runs, `Authentication.resume/2` asks the installed
`Bilimbi.Base.Tenancy.ActorVerifier` to re-prove the user. Tenancy owns the
behaviour and consumes the `:actor_verifier` contribution key; Core User
contributes the implementation, so Base never calls Core. It refuses a user
who is gone or no longer in the actor's company, and a job queued under an
impersonation that has since ended. The user's own sign-out does not cancel
their queued work. With no verifier installed, every delegated job is refused.

A module that owns a tenant-scoped invariant may still query its own tables
directly — `Bilimbi.Core.Company.PrimaryCompanyManager` locks rows and
deliberately looks across tenants to prove a company is unclaimed. That is a
different operation from serving a caller's read, and it stays explicit inside
the owning module.
