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
