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
read models and accept only documented search, filter, and sort options.

`get_role/2` returns a role with immutable capability keys and only the
principal assignments visible through the caller's company directory.
`update_role/3`, `delete_role/2`, and `replace_role_capabilities/3` reject
system roles. A custom role cannot move to another live company while any
principal remains assigned. `unassign_role/3` removes one visible assignment
by its durable ID.

`put_principal_capability/6` persists either an allow or an explicit deny.
`remove_principal_capability/5` is deliberately different: it deletes the
persisted direct rule, including a stale capability key, so evaluation falls
back to roles and the normal fail-closed behavior. Administration read models
do not join Core User or Core Company presentation data; Web composes names
through those owners' public APIs rather than making Base depend upward.
