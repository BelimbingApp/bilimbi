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

Once enabled through the [Base Schedule operator workflow](../../schedule/docs/README.md),
authorization decision logs are pruned through `Authz.prune_decision_logs/0`
by the daily schedule contributed in
[`Base Perf.Contributions`](../../perf/lib/perf/contributions.ex). Each run
reads the global **Authorization log retention** setting
(`authz.decision_log_retention_days`) and deletes decisions older than that
many days, preserving newer decisions.

## Platform capabilities

An Authz contribution may list registered keys under `platform_capabilities`.
The shared evaluator denies those keys unless the actor's scope belongs to the
platform-operator tenant, before checking direct grants, role grants, or
`grant_all`. The same rule applies to named system principals. Use this for an
authority that is platform-wide by meaning; keep route `operator: true` gates
for screens whose entire data set or workflow is platform-wide. Do not infer
platform authority from a key prefix or rely on each adapter to add its own
tenant check.

Base owns the eight `base_authz_*` tables: the five compatible ones, pinned
in its schema contract, and the Bilimbi-only
`base_authz_system_principal_capabilities`, `base_authz_field_restrictions`
and `base_authz_field_restriction_roles`, which adoption of a Belimbing
database leaves to the pending Bilimbi-only migrations. `base_authz_roles.company_id` remains
a bare nullable column in the Base migration. Core Company contributes the
named restricted foreign key and exact system/custom ownership check in its
own later migration, so Base never depends upward on Core.

## Field-level authorization

Page-level authorization says whether a record may be opened. Field access
says, field by field, which of its values a reader may see, and it is the
operator's prerogative, not a developer's: an operator holding
`admin.authz.field.manage` (the configured `tenant_owner` and `core_admin`
roles) restricts fields at Administration › Authorization › Field Access,
a table-first page whose dialog asks for the roles that still see the
fields, then the tables, then the fields of those tables, all three
multiple; the fields picked together commit as one transaction and one
restriction each (`Authz.put_field_restrictions/3`). The roles chosen are
the ones that keep seeing the field, never the ones it is hidden from: that
reading fails closed for a role created later and lets the marker name the
roles to ask for. The vocabulary is `Bilimbi.Base.Grid`'s catalog of tables and
fields; Base Authz reads that snapshot as data and depends on no Grid
module. The picker never offers a field every reader needs: a table's key,
label and time fields, hidden fields, fields a link joins on, and fields the
owning module marked `protected: true` (`Bilimbi.Base.Grid.Field`).

A restriction is tenant-scoped runtime data in the Bilimbi-only
`base_authz_field_restrictions` and `base_authz_field_restriction_roles`
tables (`Authz.put_field_restriction/4`, `put_field_restrictions/3`,
`remove_field_restriction/2`, `list_field_restrictions/1`). Each write commits with a retained
`authz.field_restriction.set` or `.removed` audit action naming who
restricted what to which roles, and the rows are audited like every write.

For a reader, `Authz.restricted_fields/1` answers `%{table => %{field =>
[role names]}}` from the roles assigned to the scope's actor in the company
they signed in at: one query for the tenant's restrictions and, only when
there are any, one for the actor's roles. Nothing is kept between calls, so a
revoked role or a lifted restriction takes effect on the next check, on any
node and inside an open LiveView, and no decision-log row is written. A
system scope, named or not, holds no roles and is withheld every restricted
field. The owning module builds its read model through `Authz.redact/3`,
which replaces each restricted field with a `Bilimbi.Base.Authz.Restricted`
marker carrying the roles that see it. The marker is explicit on purpose: an
absent field reads as "none", a blank one as "empty", and this one as "there
is a value you may not see". It renders through `<.restricted>` (Base UI):
the word "Restricted", a lock, and a tooltip that tells the person what to do
and names the roles to ask for. It offers no editor, and a create or edit
form shows the field as `<.restricted_field>`, a read-only row, never an
omitted input. Interpolated anywhere else it still reads "Restricted", never
the value, and it is not a string, so code that would compare or store it
raises.

A write that names a restricted field is refused by the owner through
`Authz.refuse_restricted_attempts/4`, with an error on that field whatever
value it carries, the stored one included, so a refusal cannot confirm a
guess. The grid catalog (`Bilimbi.Base.Grid.Catalog.for_scope/1`) leaves a
restricted field out for that reader, so the column cannot be added,
suggested, rolled up or kept in a view. The audit views follow through the
table's `record_types`: `Authz.withheld_fields_by_type/2` maps the
`auditable_type` an audit row carries to its table, Base Audit asks it
through `Bilimbi.Base.Audit.Authorization` and takes the values out of every
mutation it returns, so the record history panel and `/audit/mutations` list
a change to such a field with `<.restricted>` and without its values,
whatever audit capability the reader holds.

Core Company is the first module wired to the seam: every summary goes
through `Summary.for_scope/2`, `create_company/3` and `update_company/3`
refuse restricted fields, the administration search skips a restricted
column, and the `companies` grid table declares its `record_types` and
protects `code` and `status`. A module that owns another catalog table does
the same at its read model and its writes; the tests in
`apps/base/authz/test/field_restrictions_test.exs`,
`apps/base/grid/test/catalog_test.exs` and
`apps/core/company/test/company_lookup_test.exs` show the shape.

## A record in another company

Grants are per company, and `can/4` judges the company the user is signed in
at: a resource naming any other company is `:denied_company_scope`. When the
record being acted on belongs to another company of the same tenant, ask
`can_in_company/5`. It takes the user from the sealed scope and judges their
grants in the company named, which must be live in the scope's tenant; an
archived, missing, or other-tenant company is `:denied_company_scope`. The
decision is logged against that company with `signed_in_company_id` in the
context. A system scope is never widened this way.

## System principals

A named system principal (ADR 0017) is the identity a routine job runs as,
such as `coating.line_import`, declared by its module under the `:system_principals`
contribution with the capabilities it may be granted. On a principal's scope,
`can/4` allows a capability only when an administrator granted it to that
principal in the job's company, the module still declares it, and the
resource checks pass. There are no roles, deny rows, or `grant_all` for a
principal, and `scope_actor/1` never returns one: a principal is not a user.

Grants live in the Bilimbi-only `base_authz_system_principal_capabilities`
table, one row per company, principal, and capability; revocation deletes the
row. `grant_system_capability/4`, `revoke_system_capability/4`, and
`list_system_capabilities/2` require the scope's user to hold
`admin.authz.system-principal.grant`, `.revoke`, or `.list`; a system scope is
refused. `mix bilimbi.authz.system_principal` (`declared`, `grants`, `grant`,
`revoke`) is the operator's shell path and records `console`. Each grant and
revocation commits with a retained `authz.system_principal.granted` or
`.revoked` audit action naming who made it. Decisions log `actor_type`
`"system"`, `actor_id` `0`, and the principal's name in the context.

## Route gate

The HTTP plug and the LiveView mount gate answer from
`current_scope.capabilities`, the allowed list
`Authz.effective_capabilities/1` stored when the request scope was
rehydrated. A key present on that list is allowed without another
`Authz.can/2`, so an allowed page view does not write a decision-log row.
A key absent from the list is still evaluated with `Authz.can/2`, and that
denial is logged.

An open page does not use this shortcut for later events or for a patch that
stays on the same route. Those re-check through
`LiveAuthorization.allowed_now?/2`, one logged decision per key, so a grant
revoked after the page opened is refused. Entering a different route
refreshes the scope first, then uses the same gate.

## Re-authorizing inside a LiveView

Use `Bilimbi.Base.Authz.LiveAuthorization` for additional operation checks in
LiveView event handlers. Its [module documentation](../lib/authz/live_authorization.ex)
owns requirement shapes, live decisions, and refusal handling. The host's
page and session boundary is documented in [Live navigation](../../../web/docs/navigation.md).

## Administration facade

Administration adapters use `Bilimbi.Base.Authz`; they never query these
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

Every decision-log row names the tenant it was made in
(`base_authz_decision_logs.tenant_id`), and the page matches it exactly. A
row left with no tenant, because it has no company to derive one from, is
listed only for the platform-operator scope.

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

`explicitly_allowed?/2` answers whether the scope's user holds a known
capability through a direct allow or a role that names it; a `grant_all` role
does not count and a direct deny wins. Use it, together with `can/4`, only for
a capability that must never be conferred implicitly.

The pinned Belimbing screens search and sort joined User and Company names
before pagination. This Base-only facade intentionally does not promise those
cross-module totals or filters: its read models never join Core User or Core
Company presentation data. Web may decorate the bounded results through those
owners' public APIs, but an exact joined-name screen requires a separately
owned integration query rather than making Base depend upward.
