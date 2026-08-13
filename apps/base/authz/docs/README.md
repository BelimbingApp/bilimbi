# Base Authz

`Bilimbi.Base.Authz` owns the authorization vocabulary, roles, direct grants,
decision evaluation, and decision-log persistence. Capability definitions are
immutable module contributions; assignments remain database state.

The module deliberately has no capabilities table. Unknown capability keys
fail closed, while stale persisted grants remain intact and are reported by
diagnostics. `mix bilimbi.seeds.run` reconciles configured system roles on
first installation. Run `mix bilimbi.authz.reconcile` after later contribution
changes; application boot never mutates grants. Both paths serialize the same
explicit reconciliation, and neither deletes principal grants.

Base owns the five `base_authz_*` tables. `base_authz_roles.company_id` remains
a bare nullable column in the Base migration. Core Company contributes the
named restricted foreign key and exact system/custom ownership check in its
own later migration, so Base never depends upward on Core.

## Administration facade

Administration adapters use `Bilimbi.Base.Authz`; they never query these five
tables directly. The facade provides bounded, tenant-scoped pages for roles,
decision logs, and direct principal capabilities. Page results expose stable
read models and accept only documented search, filter, and sort options. System
role catalog rows remain visible even when a tenant currently has no companies;
assignment counts and details still follow the caller's company scope.

Compatible installations may contain effective global principal-role and
direct-capability rows whose `company_id` is null. Ordinary tenant scopes never
see or remove those rows. A platform-operator scope sees them alongside its
normal company scope and may remove them by durable row ID, which keeps global
authority auditable without exposing it to a tenant administrator.

`get_role/2` returns a role with immutable capability keys and only the
principal assignments visible through the caller's company directory.
`list_principal_role_assignments/4` returns one principal's visible persisted
assignments, including stable role facts needed to render them, in a bounded
and deterministic page. `list_principal_capabilities/2` accepts an optional
complete `principal_type`/`principal_id` pair for the same single-principal
read. Both require `:user` or `:agent` plus a positive ID; partial or other
principal identities fail closed. Their durable assignment and grant IDs feed
`unassign_role/3` and `remove_principal_capability/2` respectively.

These reads do not resolve a User or Employee and therefore cannot infer a
user's company or manufacture a tenant context. A company-less user has no
tenant-visible Authz rows unless a persisted assignment or direct capability
exists at a company the supplied `%Scope{}` can see; global rows remain visible
only to a platform-operator scope.
`update_role/3`, `delete_role/2`, and `replace_role_capabilities/3` reject
system roles. A custom role cannot move to another live company while any
principal remains assigned. Deleting a custom role intentionally relies on
database cascades to remove its grants and assignments. `unassign_role/3`
removes one visible assignment by its durable ID.

`put_principal_capability/6` persists either an allow or an explicit deny.
`remove_principal_capability/2` is deliberately different: it deletes the
visible persisted direct rule by durable grant ID, including a stale capability
key, so evaluation falls back to roles and the normal fail-closed behavior.

The pinned Belimbing screens search and sort joined User and Company names
before pagination. This Base-only facade intentionally does not promise those
cross-module totals or filters: its read models never join Core User or Core
Company presentation data. Web may decorate the bounded results through those
owners' public APIs, but an exact joined-name screen requires a separately
owned integration query rather than making Base depend upward.
