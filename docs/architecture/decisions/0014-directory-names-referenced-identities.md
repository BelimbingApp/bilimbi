# ADR 0014: the principal directory names referenced identities, not only authz principals

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** opus-4.8
**Scope:** Extends the ADR 0011 seam with an `:employee` kind so Core screens can
name employees they reference across an upward edge; reframes the seam's scope.
**Last Updated:** 2026-08-22
**Extends:** `0011-principal-directory-seam.md` (claude-opus-5). This ADR does
**not** amend 0011; it builds on it. 0011's contract, placement, and query
boundary are unchanged.

## Context

ADR 0011 gave three **Base** screens (`/system/sessions`,
`/authz/principal-capabilities`, `/authz/principal-roles`) a seam to name the
Core principals they reference by id, because Base must not depend on Core. Its
`Provider.kind()` is `:user | :agent` — the two `principal_type`s Base Authz
stores in `principal_capabilities`. Core User answers `:user`; Core Employee
answers `:agent`.

A fourth screen now needs the same thing, one layer up. `#622` finding 3: the
company **departments** table must show a **Head**, and the head is
`company_departments.head_id -> employees` (`:nilify_all`, i.e. *any* employee).
Core Company cannot name it: `core/employee` depends on `core/company`, so
naming the head from Company would close an upward edge — the same edge #439/#570
established you may not reflect around.

This differs from 0011 in two ways, and both matter to the decision:

- The consumer is a **Core** screen (Core Company), not a Base one. The seam
  still fits: `base/principal_directory` is downward from `core/company`, and the
  provider is downward from `core/employee`, so `Company -> directory <- Employee`
  is all downward, no cycle.
- The referenced identity is **not an authz principal**. A department head is an
  employee; most are not agents and appear in no `principal_capabilities` row.
  The existing `:agent` provider cannot name them — it answers only for the
  agent kind — so this genuinely needs a new kind, not the existing one.

## Decision

**Add an `:employee` kind to the directory, and state plainly that the seam
names the identities a screen references — of which authz principals are the
subset stored in `principal_capabilities`.**

Concretely:

1. `Provider.kind()` becomes `:user | :agent | :employee`. Its documentation
   changes from "the principal kinds Base Authz stores" to "the kinds of
   identity a screen references and cannot name itself; `:user`/`:agent` are the
   authz-principal subset, `:employee` is a Core identity named on Core screens."
2. Core Employee contributes a second provider answering `:employee`, resolving
   any employee by id through the same tenant-scoped `get_tenant_employees/2`
   the `:agent` provider uses (archived companies included, for 0011's reason —
   a grant, or a headship, outlives its company being archived). Because one
   module now contributes two providers, the `principal_directory` contribution
   accepts **a list of provider modules** (as well as the single atom it accepts
   today), each keyed into the directory's `%{kind => provider}` map by its own
   `principal_kind/0`. That is a small, downward change to the contribution's
   validator and aggregation; the `Provider` behaviour stays one-kind-per-
   provider. (Making a provider answer *several* kinds was considered and
   rejected: it would change the behaviour every provider implements, for no
   gain over a two-element list.)
3. Every part of 0011's contract carries over unchanged: candidate set supplied
   by the screen, `{kind, id}` keying, tenant scoping by construction, name
   search that refuses rather than degrades, name sort that degrades to durable
   id with a visible notice, exact totals, and archived/cross-tenant ids that
   resolve to no name but keep their row.

### Why this is honest, not dishonest naming

The concern is that an employee is not a "principal", so an `:employee` kind in
a module named *PrincipalDirectory* misnames it. This is a **name** imperfection,
not a **contract** one. 0011's contract was always "name the `{kind, id}`
identities a screen references, across a boundary the screen cannot cross"; the
word *principal* recorded the first consumers (authz screens), not a limit on
what the seam may name. `{kind, id}` keying already generalises. Extending the
kind set is honest to the contract; it only stretches the label.

The module is **not** renamed. An `IdentityDirectory` rename is heavy churn for a
required Base module — two declared-dependency edges, a full rebuild, and every
reference — for a minor gain in label precision. Instead the documentation states
the reframing, and the label is read as historical.

## Alternatives rejected

- **(b) An employee-owned discovered panel for the departments section**
  (the #612 machinery). Rejected as **mis-owned**: `company_departments` belong
  to Core Company. A discovered panel owned by Core Employee rendering Company's
  departments inverts ownership, and a whole panel for a single column is
  disproportionate. Discovered embeds fit a *section a module owns*; Employee
  does not own departments.
- **Reflection from Company into Employee** (`Code.ensure_loaded?` + `apply`).
  The same upward-edge-hidden-from-graph-validation defect 0011 rejected for
  Base; no better here.
- **Renaming the module to `IdentityDirectory`.** Rejected above: cost without
  proportionate benefit.

## Consequences

- One new provider kind and one new Core Employee provider; the four→five
  consumer count and the seam's placement are unchanged. No new module.
- The `:agent` and `:employee` providers share resolution logic
  (`get_tenant_employees/2`) but answer different kinds, because the kind
  reflects how the screen references the identity, not a type filter. The
  duplication is one differing line and is the honest cost of one-kind-per-
  provider.
- The `:employee` kind pays forward: any Core screen naming an employee it
  cannot name itself — a supervisor on an employee page, an actor on a future
  Core audit view — uses the same seam rather than a new mechanism each time.
- The departments **Head** column (the consumer of this kind) lands in a
  separate change, mirroring how 0011's seam and its consuming screens were
  split.

## Governance note

ADR 0011 is claude-opus-5's and Accepted. Who may amend an Accepted ADR is itself
open (`#513`), so this decision is recorded as a *new, extending* ADR rather than
an edit to 0011. If the team later prefers the extension folded into 0011, that is
0011's author's call, not this ADR's.
