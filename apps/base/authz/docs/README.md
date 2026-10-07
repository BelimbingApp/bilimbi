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

Base owns the six `base_authz_*` tables: the five compatible ones and the
Bilimbi-only `base_authz_system_principal_capabilities`. `base_authz_roles.company_id` remains
a bare nullable column in the Base migration. Core Company contributes the
named restricted foreign key and exact system/custom ownership check in its
own later migration, so Base never depends upward on Core.

## Field-level authorization

Page-level authorization says whether a record may be opened. A field
policy says, field by field, which of its values the reader may see. The
owning module declares one `Bilimbi.Base.Authz.FieldPolicy` for its read
model, naming each sensitive field with the capability that shows it, and
builds every summary through `Authz.redact/3`, which replaces each field the
scope's actor lacks the key for with a `Bilimbi.Base.Authz.Withheld` marker.
The marker is explicit on purpose: an absent field reads as "none", a blank
one as "empty", and this one as "there is a value you may not see". It
renders through `<.withheld>` (Base UI) and offers no editor; interpolated
anywhere else it still reads "Withheld", never the value, and it is not a
string, so code that would compare or store it raises.

The decision is made once per call from the reader's effective allow list,
the same list the route gate reads, so a field and the pages that need its
capability agree, and no decision-log row is written: nothing was attempted.
`Authz.effective_capabilities/1` keeps nothing between calls: every ask reads
the grants afresh, so a revoked capability stops working on the next check, on
any node and inside a LiveView that is already open. A whole field policy is
one evaluation (`Authz.withheld_fields/2` asks once however many fields it
names, and `redact/3` once for a whole list).
A named system principal is judged by `can/4`. An anonymous system scope
names nobody and is withheld every field. A write to a withheld field is
refused by the owner through `FieldPolicy.refuse_changes/2`, with an error
on that field. The owner's grid fields carry the same key
(`Bilimbi.Base.Grid.Field`), so the column the record page withholds is
not in that reader's catalog either.

The audit views follow the same policy. Base Audit cannot depend on Authz
(Authz depends on Audit), so a module also names its policy in its `:authz`
contribution, `field_policies`, keyed by every `auditable_type` its rows are
recorded under; the validator rejects a type declared twice or a policy
naming an unregistered capability. `Authz.withheld_fields_by_type/2` answers
for many types in one evaluation through Base Audit's
`Bilimbi.Base.Audit.Authorization` seam, and `Bilimbi.Base.Audit` takes the
withheld values out of every mutation it returns, so the record history
panel, the mutations browser at `/audit/mutations` and any other caller list
a change to such a field with `<.withheld>` and without its before and after
values, whatever audit capability the reader holds.

The first policy is Core Company's: `tax_id` and `email` need
`admin.company.sensitive.view`, which the configured `tenant_owner` role
receives. An existing installation carries it into its database with
`mix bilimbi.authz.reconcile`; until then only `grant_all` roles see those
two fields.

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
