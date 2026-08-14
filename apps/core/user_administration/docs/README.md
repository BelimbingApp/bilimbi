# Core User Administration read contract

`Bilimbi.Core.UserAdministration` owns the bounded Users administration index
read and web adapter established by ADR 0007. It contributes exactly the
capability-gated `/users` route. Core User continues to own account commands
and the `/users/new`, `/users/:id`, and `/users/:id/edit` adapters. This package
owns no command, migration, schema contract, menu, or capability contribution.
Callers pass a validated `%Bilimbi.Base.Tenancy.Scope{}` and strict normalized
options to `list_users/2`; the only result is a schema-free `%Page{}` containing
UI-safe `%Entry{}` and `%Role{}` summaries.

## Visibility and options

The read starts from tenant-scoped Companies. Users at archived Companies stay
visible with the archived Company name and flag. A null Company affiliation or
an affiliation to another tenant is absent. This is data visibility, not actor
authorization; the web adapter enforces `admin.user.list` before it calls the
facade.

The adapter keeps `active_nav` at `admin.user`, so Core User's existing menu
contribution remains the navigation owner. Create, view, update, and delete
controls are gated by their existing Core User capabilities. Deletion calls
only Core User's public tenant-scoped APIs, protects the signed-in account,
reports disappearance races, and presents archived-company accounts as
read-only.

Options accept only a keyword list containing the following normalized values:

- `search`: `nil` or at most 255 bytes; `""` and exact `"0"` disable search;
- `role_ids`: at most 100 unique positive integer IDs, with OR semantics;
- `sort_by`: `:name`, `:email`, `:company_name`, or `:created_at`;
- `sort_dir`: `:asc` or `:desc`;
- `page`: an integer from 1 through 1,000,000; and
- `page_size`: exactly `10`, `25`, `50`, or `100`.

Defaults are no search or Role filter, Name ascending, page 1, and 25 entries.
Search uses PostgreSQL `LIKE`, including its case behavior and `%`/`_` wildcard
meaning, around a parameterized contains pattern. The deliberate page cap
keeps the largest supported page-size offset below 100 million rows, far below
PostgreSQL's signed-bigint `OFFSET` ceiling, while rejecting impractical URL
inputs before arithmetic reaches the adapter. Every primary ordering ends with
User ID descending. Empty and out-of-range pages keep truthful totals.

The adapter accepts plain URL and form values and normalizes them into this
strict contract without creating atoms. Page sizes clamp upward over `10`,
`25`, `50`, and `100`, so `1` becomes `10`, `30` becomes `50`, and `9999`
becomes `100`. Empty search and exact `"0"` retain their PHP-falsey meaning.
Changing search, Roles, page size, or sorting resets to page 1; pagination
alone preserves the other filters. A first Created sort uses descending order,
while Name, Email, and Company begin ascending.

Role summaries use the integration-only containment rule from ADR 0007. The
assignment must be visible through a live in-scope Company (or the documented
platform-global case); custom Roles must be non-system and owned by a live
in-scope Company; system Roles must be marked system and have no owning
Company. Missing, foreign, and archived-owned Roles are ignored. Duplicate
visible assignments produce one summary per durable Role ID ordered by
`{name, code, id}`. This does not modify or replace Base Authz's public
administration contract.

## Persistence containment

Only private `Bilimbi.Core.UserAdministration.Query` may use the four
schema-less sources approved by ADR 0007. `ConsumedRelations` version 1 checks
the owner, migration version, type, and nullability of each consumed column
against the owners' public `SchemaContract.tables/0` output before a page read.
That structural check does not grant authority.

Package architecture tests inspect parsed Elixir AST and source positions.
They enforce one physical source site per reviewed relation, exact field sets
for each source binding, fixed relation sources and fragments, the absence of
owner schemas and persistence writes/escapes, and the exact descriptor graph.
Expanding or copying the exception requires an ADR and manifest review, not a
local query edit.

## One-statement and EXPLAIN evidence

One facade call produces one parameterized PostgreSQL statement. Its fixed CTE
pipeline establishes tenant Companies, valid visible Roles, filtered Users,
the filtered count, the ordered bounded page, and page-only Role aggregation.
The final count envelope leaves one sentinel row for an empty or out-of-range
page. Consequently count, page, archived Company facts, and Role summaries
share one PostgreSQL statement snapshot; the application never receives an
unbounded tenant collection.

The executable performance review in `test/performance_test.exs` uses
PostgreSQL 18 with 40 Users across live and archived Companies and 14 Role
assignments. It runs unfiltered, selective/nonselective search, both directions
of all four sorts, Role-only and combined filters, a deep page, and an
out-of-range page. For every scenario it:

- observes exactly one Repo telemetry query for `list_users/2`;
- executes `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` with the captured bound
  parameters;
- verifies the root returns no more rows than the requested bounded page;
- verifies the plan reports buffer usage and no temporary-block spill; and
- treats execution time as review evidence, not a cardinality-independent CI
  latency promise.

On the 2026-08-14 local PostgreSQL 18 review, all 15 scenarios passed. The
analyzed execution times ranged from 0.186 ms to 1.444 ms, root rows stayed at
or below 25, and no temporary blocks were read or written. The fixture is a
practical regression shape, not a production-scale claim. Before increasing
cardinality or changing the query, rerun the same matrix and review plans and
buffers. Any index justified by measured evidence belongs in a separately
reviewed migration owned by the table's existing module; this package owns no
index, view, or function.
