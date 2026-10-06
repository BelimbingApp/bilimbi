# ADR 0019: Grid table catalog as a contribution consumer

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Contribution consumer for the field-and-link catalog behind flexible tables
**Last Updated:** 2026-09-27

## Context

ADR 0004 established the contribution contract, and ADRs 0009, 0011, 0012,
0016 and 0017 added peer consumers. Every module keeps its schemas, queries
and table names behind its own API, so no shared surface could let a person
pick a column from another table without that module writing the join.

Flexible tables need exactly that: a person adds a column by walking a link
(`user → company → country`) and the platform builds the statement. The
vocabulary of tables, fields and links, and the rows an account may read of
each, belong to the owning modules; the walking, the statement and the
rendering are platform work.

## Decision

1. `:grid` is adopted as a **peer consumer** in the same contribution
   contract, validated by `Bilimbi.Base.Grid.ContributionValidator`.
2. A contribution is `%{tables: [table]}`. A table declares its stable id,
   label, the capability that reads it, a `Bilimbi.Base.Grid.Source`
   module, its key, label and time fields, its fields with types, and its
   links. A link is `:one` or `:many`, joins `on: {from_field, to_field}` or
   `via: {module, function}` (an edge query), and may start at another
   module's table when the declaring module depends on that one.
3. **The owner scopes its rows.** `Source.query/1` returns the rows the
   scope may read, with the owner's tenant, soft-delete and company
   filters applied. The grid wraps every source in a subquery and adds no
   tenant predicate of its own; a path's every hop carries its owner's
   boundary. A source or edge module must belong to the declaring
   module's OTP application, so no module can catalog another's table
   under its own capability.
4. **Visibility is by capability, once.** The catalog an account uses holds
   only the tables whose capability its effective permissions allow. Paths
   resolve against that catalog, so a table left out cannot be reached.
5. **The validator fails the build** on a duplicate table id, a link to an
   undeclared table or field, a `:one` link that does not join on the
   target's key, a source without the behaviour, or an edge outside the
   declaring application.

## Consequences

- Any installed module puts its tables in the catalog by adding a `:grid`
  key to its provider; Core User, Company, Employee, Address and Geonames
  do so from this ADR forward.
- Reads through the catalog are not the sibling-private-table access ADR
  0007 forbids: the owner declares what is readable and how it is scoped,
  and the grid composes only declared sources.
- Every grid statement is one parameterized SELECT; a many-link never
  multiplies root rows, and the planner's cost estimate is surfaced so a
  heavy set of rollups warns before it is run again.
