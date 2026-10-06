# ADR 0019: Grid table catalog as a contribution consumer

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Contribution consumer for the field-and-link catalog behind flexible tables
**Last Updated:** 2026-10-06

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
6. **No source query is built at boot.** The validator checks declarations
   only. Which key of a source's query a field is read from is settled the
   first time a catalog is built for a scope that may read the table, and
   a field no key answers to is refused then, naming the field. A source
   may therefore ask another module's public API for what bounds its rows
   while it builds its query; it never composes that module's query or
   table into its own statement.

## Consequences

- Any installed module puts its tables in the catalog by adding a `:grid`
  key to its provider; Core User, Company, Employee, Address and Geonames
  do so from this ADR forward.
- Reads through the catalog are not the sibling-private-table access ADR
  0007 forbids: the owner declares what is readable and how it is scoped,
  and the grid composes only declared sources. A table with no tenant
  column of its own stays inside that rule: the users source filters on
  the company ids `Bilimbi.Core.Company.list_tenant_company_ids/1`
  returns, and its statement reads only `users`.
- The application boots, and the catalog validates, on a database with no
  tables. The cost is that a field naming no source key is caught by the
  host's catalog test and at first use rather than at boot.
- The consumer of the catalog is a list page
  (`Bilimbi.Base.Grid.Web.PageColumns`), which attaches walked columns to
  the rows it already lists. Every such statement is one parameterized
  SELECT bounded by that page of keys, and a many-link never multiplies
  root rows. The one statement that reads a whole table, the range a bar
  or band scales to, reports the planner's cost so a heavy one warns.
