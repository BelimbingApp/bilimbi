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
Lenses are `value`, `bar` and `band`; `trend` is reserved.

`Bilimbi.Base.Grid.View` is the whole state of a grid and lives in the URL
(`cols`, `lens`, `z`, `sort`, `dir`, `q`, `page`, `per_page`, `group`, `v`).
`Bilimbi.Base.Grid.Web.GridLive` is `/grid` and `/grid/:table`.
`Bilimbi.Base.Grid.Web.PageColumns` lets a list page keep its own query
and gain walked columns; the users and companies lists use it.
`Bilimbi.Base.Grid.SavedViews` keeps an account's own views in
`ui.grid.views` and the company's shared views in `ui.grid.shared_views`;
a saved view opens at `/grid/<table>?v=<slug>` (or `v=shared:<slug>`),
and the same address opens in a workspace tile.

Grouping sorts by the grouped column and heads each run of equal values;
it is not a GROUP BY. Dragging a heading onto the drop zone groups;
dragging a chip or a heading onto another reorders.

## What remains

- A pivot (rows by a second column's values) and a cross-tile join drag.
- The `trend` lens: per-period counts over a dated many-link as a
  sparkline, and a change-since-a-date lens.
- Server-side grouping with per-group aggregates.
- Per-column filters beyond the root text search.
- Refiltering following tiles from a grid's follow channel.
- Base Authz tables (roles, grants) in the catalog.
