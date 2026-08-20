# ADR 0011: Principal directory seam and its query boundary

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** claude-opus-5
**Scope:** Ownership, module placement, and the query boundary for naming Core
principals on Base-owned screens
**Last Updated:** 2026-08-21
**Supersedes:** nothing. `0010` is reserved by
`docs/architecture/0010_composition-model.md` and must not be reused for an ADR.

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

## Decision 2: the directory ranks the principals a screen actually references

### Why "the directory owns the paginated read" is not available

The obvious contract — the directory takes search, sort, offset and limit and
returns a named page plus an exact total — **cannot serve either consumer**,
because in neither case is the page a page of principals:

- `/authz/principal-capabilities` pages `PrincipalCapability` rows
  (`administration.ex:170-203`).
- `/authz/principal-roles` pages assignments (`:214-249`).
- `/system/sessions` pages session rows.

A page of grants sorted by principal name is a join the directory cannot perform,
because Base owns the grants and Core owns the names. No placement changes that.

### Principal identity is composite

An Authz principal is `{principal_type, principal_id}`. A user with id 5 and an
agent with id 5 are different principals, and `principal_capabilities` stores
both kinds in one table. **Every part of this contract is keyed on the pair**:
directory arguments, the returned name map, the database filter, and the
ordering rank. An id-only array would decorate or rank the wrong kind, silently,
and only for installations where both id spaces overlap — which is to say,
eventually.

Ties break deterministically on normalised name, then type, then id, so two
principals with the same display name order the same way on every page and every
run.

### The consumer names its candidates first

The directory is **not** asked for every principal in the tenant. Base owns the
grants, so Base can compute exactly which principals its visible dataset
references, before pagination:

```
SELECT DISTINCT principal_type, principal_id
FROM <the already visibility-filtered, already-filtered query>
```

That set is passed to the directory, which scopes it to the actor's tenant,
resolves names, applies any name search, and returns the ranked survivors. Base
then filters and orders its own query by that rank — the existing
`array_position` mechanism (`administration.ex:465-473`) — and only then applies
`offset`/`limit`.

The set is therefore bounded by **what the screen references**, not by tenant
size. A tenant with fifty thousand users and a Roles screen showing grants for
six principals resolves six. Fetching the whole tenant would have degraded that
screen for no reason, which is what an earlier draft of this ADR specified.

Ordering still happens in the database before limiting, which is what ADR 0007
requires and what #439 got wrong.

### The ceiling, and what happens above it

A ceiling still exists, because a screen with no filters can reference many
principals. It applies to the **referenced candidate set**, not the tenant.

Above it, and when no provider is installed, the affected principals render as
their durable type and id — the #285 out-of-scope presentation, which already
exists and already reads correctly.

### Fallback must not silently change the query

Falling back to ids while a name sort or name search is active would answer a
different question than the one asked. So:

- **Name search cannot degrade.** If candidates cannot be resolved, the search
  fails visibly rather than returning unfiltered rows; a search that silently
  matches nothing and a search that silently matches everything are both lies.
- **Name sort degrades to the durable order** (`id`), and the screen shows a
  notice saying names are unavailable and the sort is by id. URL state is
  normalised to the sort actually applied, so a reload does not silently reapply
  a sort that is not in effect and a shared link shows what its sender saw.
- **Totals stay exact.** The count query is Base's own and does not depend on the
  directory; degradation changes ordering and naming, never membership — except
  under name search, which is refused rather than approximated.
- **Archived, deleted and cross-tenant principals** resolve to no name and take
  the durable presentation. They are not errors and must not remove the row: a
  grant to a deleted principal is exactly what an operator needs to see.

## Consequences

- One new required Base module and one new contribution consumer.
- `base/session` and `base/authz` each gain one declared dependency; both are
  downward and neither closes a cycle. A module-graph edge requires
  `rm -rf _build` and a full rebuild.
- Two Core implementations, validated the way `CompanyDirectory`'s is: the module
  loads, declares the behaviour, and belongs to the contributing OTP app.
- Screens pay for the principals they reference, not for the tenant. A screen
  showing six principals resolves six.
- Above the ceiling, or with no provider installed, screens keep working with
  ids instead of names — visibly, by contract, and with the sort they actually
  got reflected in the URL.

## Alternatives rejected

**Reflection from Base into Core** (#439). Not loadable from the owning package;
hides an upward edge rather than removing it.

**Contract in `base/ui`.** Too narrow an owner for tenant isolation and query
semantics, and forces an opaque scope type.

**Resolving every principal in the tenant.** Specified in the first draft of this
ADR and rejected on review: it degrades a screen referencing a handful of
principals because some other part of the tenant is large. The consumer knows its
candidates and should say so.

**Id-only directory arguments.** Conflates a user and an agent that share a
numeric id.

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

## Outcome

Implemented in five merged pull requests, closing #441:

| Step | PR | What it added |
|---|---|---|
| 1 | #471 | the module, the `Provider` behaviour, `rank/3`, the contribution validator |
| 2 | #481 | Core User's `:user` provider |
| 3 | #486 | Base Session consuming it — closed #285 |
| 4 | #492 | Core Employee's `:agent` provider |
| 5 | #503 | Principal Roles and Principal Capabilities |

Two things the ADR did not anticipate, both worth recording because they are the
kind of thing the next seam will hit too.

**A consumer's empty value has a shape, and the registry was not asking.**
`ContributionRegistry` answered a blanket `[]` for any consumer nothing
contributed to, without calling that consumer's validator. Four of five
consumers are list-shaped so nothing noticed; this directory's is a map, and
`Map.fetch/2` on a list raises. The "installed-module absence degrades
honestly" property this ADR claims was therefore false from step 3 until #499
fixed the registry. Found by amp/gpt-5.6-high, filed as #496.

**Search reaches only what the seam exposes.** Belimbing's principal screens
also search `users.email`. `Provider` declares `names/2` and nothing else, so
that third of the search is absent. Whether to widen the behaviour — an
optional `search/2` returning matching ids, letting Core decide what it matches
on without Base learning what an email is — is open as #500. It was left open
deliberately rather than settled inside an implementation PR.

One divergence from Belimbing is deliberate and is not a gap: Belimbing's join
is unscoped and names any user id it finds. Naming here resolves only inside the
actor's validated tenant scope, per the hybrid ruled on #285.
