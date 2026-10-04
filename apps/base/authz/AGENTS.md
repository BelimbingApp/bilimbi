# Base Authz changes

On the decision path, prove the actor's company and load role ids in one
statement through `EffectivePermissions`. Do not call `company_ids/1` and
`company_in_scope?/2` as two company reads: `company_ids/1` loaded every live
company through `list_companies/1`, and `company_in_scope?/2` fetched one full
row. A directory that implements `live_company_ids_query/1` selects live ids
only. `list_tenant_company_ids/1` includes archived companies and is the wrong
set here.

The route gate reads `current_scope.capabilities`. Do not call `Authz.can/2`
for a key already on that list; a missing key still goes through `can/2` so
the denial is logged. Events on an open page still use
`LiveAuthorization.allowed_now?/2`. See
[`docs/README.md`](docs/README.md#route-gate).

Declare operator-tenant-only authority through the contribution's
`platform_capabilities` list, which the shared evaluator enforces for direct,
role, `grant_all`, and named system-principal grants. Use route `operator:
true` for a screen whose whole workflow is platform-wide. See
[`docs/README.md`](docs/README.md#platform-capabilities) for the contract; do
not replace it with key-prefix checks or adapter-only authorization.
