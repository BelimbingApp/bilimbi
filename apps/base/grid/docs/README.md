# Base Grid

Base Grid owns flexible tables: the catalog every module declares its
tables into, the paths a person walks through it to pick columns without
writing a join, the one statement that answers them, and the surfaces
that show the result at any zoom, through lenses, and as saved views.

## The model

A module puts a table in the catalog through its `:grid` contribution
(ADR 0018): the table's `fields`, its `links` to other tables, the
`capability` that reads it, and a `Bilimbi.Base.Grid.Source` whose
`query/1` returns the rows a scope may see, with the owner's own tenant,
soft-delete and company filters applied. The grid wraps every source in a
subquery, so every hop of a path carries its owner's boundary and the grid
never adds a tenant predicate of its own. A link is `:one` (a foreign key
to the target's key, or an edge query that yields one row per parent) or
`:many` (the reverse, or a polymorphic attachment table). A module that
depends on another may declare a link that starts at the other's table,
because the module that owns the edge is the one that knows it.

`Bilimbi.Base.Grid.Catalog.for_scope/1` reads the installed snapshot once
and keeps the tables whose capability the actor holds. Every later call
takes that catalog, so there is no spelling of a path that reaches a table
the account may not read.

A column is a spec (`Bilimbi.Base.Grid.Column`): `name`, `company.name`,
`company.parent.name` through one-links; `employees:count`,
`lines.qty:sum`, `tags.name:list`, `lines.sku:latest` through a many-link,
which rolls the reached rows up into one cell. A path holds at most one
many-link, so the root row count never changes whatever is added.
`Bilimbi.Base.Grid.Query` builds one PostgreSQL statement: a LEFT JOIN
per one-link prefix, one grouped subquery per many-link carrying every
aggregate over it, positional bindings and select keys so no atom is ever
made from a typed string. `Bilimbi.Base.Grid.query/4` adds sort, search
over the root's text fields, a window, the value range of every numeric
column across the whole set, and the planner's cost estimate from EXPLAIN.
`attach/4` fetches walked columns for rows a page already has; `expand/4`
lists the rows a rollup collapsed.

## The surfaces

`Bilimbi.Base.UI.Components.flex_table/1` is the component; it is
presentation only and pushes one event with an `op`. Its `FlexTable` hook
draws the compact and carpet modes on a canvas from windows the host
pushes, so the browser renders only what is visible; the full mode is a
table. `Bilimbi.Base.Grid.Zoom` fixes the bands (row height at most 6 px is
the carpet, at most 20 px compact, above that the table) and
`Bilimbi.Base.Grid.Lens` prepares a cell for every mode at once: text, its
position on the column's range, and the band that position falls in.

`Bilimbi.Base.Grid.View` is the whole state of a grid and lives in the URL;
its module doc lists the keys, and `v` names a saved view.
`Bilimbi.Base.Grid.Web.GridLive` is `/grid` and `/grid/:table`.
`Bilimbi.Base.Grid.Web.PageColumns` lets a list page keep its own query
and gain walked columns; the users and companies lists use it.
`Bilimbi.Base.Grid.SavedViews` keeps an account's own views in
`ui.grid.views` and the company's shared views in `ui.grid.shared_views`;
a saved view opens at `/grid/<table>?v=<slug>` (or `v=shared:<slug>`),
and the same address opens in a workspace tile.

Grouping sorts by the grouped column and heads each run of equal values;
it is not a GROUP BY. Dragging a heading onto the group corner groups, and
onto the pivot corner pivots a grouped grid: `Grid.pivot/5` counts root rows
per pair of values in one GROUP BY statement, the grouped column's values
as rows and the pivoted column's values (the first 24 by name, the rest
folded into "Other") as columns, with a total, after a first column that
names each row. It reads a bounded number of pairs; a row the bound cut
short is left out, never shown with a partial total, and the page says the
pivot is truncated. Dragging a chip or a
heading onto another reorders.

Lenses are `value`, `bar`, `band`, and, for a count or sum over a dated
many-link, `trend` (the aggregate per calendar month over the last twelve,
a sparkline) and `delta` (the aggregate as of a date, through a FILTER in
the same grouped subquery).
The date lives in the view.

Inside a tiled workspace a grid can follow what another tile selects: a
table declares the module kind whose facts name its rows (`record_kind`),
the page tells the workspace the kinds it follows itself
(`Bilimbi.Base.UI.Workspace.follow/2`), and a selection narrows the grid
to the rows reaching that record, kept in the address as `follow` and
`focus`. Shared views may be limited to role codes, as shared workspace
layouts are.

## What remains

- In-cell editing at full zoom: the table shows full text but does not edit.
- Cross-tile join by drag.
- Server-side grouping with per-group aggregates beyond the pivot's counts.
- Per-column filters beyond the root text search.
- Base Authz tables (roles, grants) in the catalog.
