# ADR 0010: Principal directory seam and its query boundary

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** claude-opus-5
**Scope:** Ownership, module placement, and the query boundary for naming Core
principals on Base-owned screens
**Last Updated:** 2026-08-20

## Context

Three Base screens identify people by database id where Belimbing shows a name:

| Screen | Owner | Shows |
|---|---|---|
| `/system/sessions` | `base/session` | `User 91` |
| `/authz/principal-capabilities` | `base/authz` | principal kind + id |
| `/authz/principal-roles` | `base/authz` | principal kind + id |

Belimbing joins `users` directly. Bilimbi cannot: Base must not depend on Core
(ADR 0003; AGENTS.md). #439 attempted `Code.ensure_loaded?/1` plus `apply/3` from
`base/session` and was rejected — from the owning package
`Bilimbi.Core.User` is `{false, :nofile}`, so the screen worked only because the
Web host's dependency closure happened to load it. Reflection hid the upward edge
from graph validation rather than removing it.

`/authz/decision-logs` is **out of scope**: #185 ruled its actor ids deliberate,
settled by #213. An audit row is evidence of the moment; a read-time join would
show the name the actor has now.

The naming rule itself is already ruled (#285): a principal inside the actor's
validated tenant shows its name; one outside shows the durable type and id;
`user_id` nil shows `Guest`.

## Decision 1: a dedicated `base/principal_directory` module

The seam lives in a new required Base module rather than in an existing one.

`base/session` declares `base/database`, `base/module_registry`, `base/ui`.
`base/authz` declares those plus `base/settings` and `base/tenancy`. The common
reachable set is `base/database`, `base/module_registry`, `base/ui` — and **none
of the three can name `Scope.t()`**, because `base/tenancy` depends on
`base/ui` and on `base/database`, so either would close a cycle.

Placing the contract in `base/ui` was proposed and withdrawn. Two reasons:

- The seam carries tenant isolation, name search, stable ordering, exact totals
  and pagination-before-limiting. Those are directory and query semantics with
  security consequences, not presentation. A screen that names a person is the
  consumer, not the owner.
- Avoiding `Scope.t()` would have meant an opaque `term()` at a tenant-security
  boundary — the same objection that rules out passing a bare `tenant_id`, one
  step further along.

A new module has no inbound edges, so it may depend on `base/tenancy` and expose
`Scope.t()` honestly. The constraint that forced the opaque type was an artefact
of choosing a module that already had a cycle, not a property of the problem.

`base/session` and `base/authz` each gain one declared dependency on it. Core
User and Core Employee own their implementations and contribute them.

This adds a fifth contribution consumer, changing the four-consumer model in
`Bilimbi.Base.ModuleRegistry.ContributionRegistry`. That model is a decision, not
a constraint to route around.

## Decision 2: the directory supplies ids and an order; it does not own a page

### Why "the directory owns the paginated read" is not available

The obvious contract — the directory takes search, sort, offset and limit and
returns a named page plus an exact total — **cannot serve either consumer**,
because in neither case is the page a page of principals:

- `/authz/principal-capabilities` pages `PrincipalCapability` rows
  (`administration.ex:170-203`).
- `/authz/principal-roles` pages assignments (`:214-249`).
- `/system/sessions` pages session rows.

A page of grants sorted by principal name is a join the directory cannot perform,
because Base owns the grants and Core owns the names. Nothing about placing the
contract better changes that.

### What is available

The existing `CompanyDirectory` already solves the identical problem for
companies, and its mechanism transfers:

```elixir
# administration.ex:465-473
order_by(query, [grant], [
  {^direction, fragment("array_position(?::bigint[], ?)", ^ids, grant.company_id)},
  {^direction, grant.id}
])
```

The LiveView loads the complete in-scope company set in `mount/3` and passes
every id as `company_order`. Ordering therefore happens **in the database, before
`offset`/`limit`**, which is what ADR 0007 requires and what #439 got wrong.

So the contract is:

- `principals_in_scope(scope, kind)` — every in-scope principal of that kind, id
  and name, ordered by the name being displayed, case-insensitively.
- `names(scope, ids)` — a bounded map for decorating rows already selected.

`names/2` alone is insufficient and must never be the only callback: it can only
decorate a page some other ordering chose. It exists because a screen that does
not sort by name should not pay for the full set.

### The bound, stated rather than assumed

`principals_in_scope/2` is proportional to principals per tenant. Companies get
away with this because a tenant has few; users and agents do not have that
property, and pretending otherwise is how this contract would fail in
production rather than in review.

Therefore:

- The implementation **must** be tenant-scoped by construction, as
  `Core.User.get_tenant_users/2` already is.
- The contract carries an explicit ceiling. Above it the implementation returns
  `{:error, :too_many_principals}` and the consumer falls back to id ordering
  with the durable type and id — the #285 out-of-scope presentation, which
  already exists and already reads correctly.
- The ceiling is a stated number, not a silent truncation. Belimbing's schedule
  board fetches at most 500 rows and filters in memory; #442 correctly refused to
  copy that. Truncating a name index would be the same defect: a sort that
  silently covers part of the set is worse than no sort, because it looks like
  one.

Name **search** uses the same set: the directory returns matching in-scope ids
and the consumer filters `principal_id in ^ids` before paginating. It is bounded
by matches rather than by tenant size, and it shares the ceiling.

## Consequences

- One new required Base module and one new contribution consumer.
- `base/session` and `base/authz` each gain one declared dependency; both are
  downward and neither closes a cycle. A module-graph edge requires
  `rm -rf _build` and a full rebuild.
- Two Core implementations, validated the way `CompanyDirectory`'s is: the module
  loads, declares the behaviour, and belongs to the contributing OTP app.
- Screens that sort by principal name pay for the in-scope set on mount. Screens
  that only display names pay for a bounded `names/2` call.
- A tenant above the ceiling keeps working, with ids instead of names, visibly
  and by contract rather than by accident.

## Alternatives rejected

**Reflection from Base into Core** (#439). Not loadable from the owning package;
hides an upward edge rather than removing it.

**Contract in `base/ui`.** Too narrow an owner for tenant isolation and query
semantics, and forces an opaque scope type.

**Bare `tenant_id` across the seam.** Nameable by every module, and unvalidated —
it moves the privacy guarantee from the type onto every call site.

**Directory owns the paginated read.** Not applicable: no consumer pages a list
of principals.

**Denormalising names into Base tables.** Would make Base own a copy of Core data
that goes stale on rename, which is exactly why #185 keeps decision-log actors as
ids.

**Leaving all three screens on ids.** Still the fallback above the ceiling, and it
remains correct for `/authz/decision-logs`. Rejected as the default because
Belimbing names these people and #285 ruled the hybrid.
